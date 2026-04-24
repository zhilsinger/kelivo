import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../../core/models/chat_input_data.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/spawned_task.dart';
import '../../../core/models/token_usage.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/chat/chat_orchestrator_service.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../utils/assistant_regex.dart';
import '../../../core/models/assistant_regex.dart';
import '../../../utils/markdown_media_sanitizer.dart';
import '../services/message_generation_service.dart';
import '../services/tool_approval_service.dart';
import 'chat_controller.dart';
import 'generation_controller.dart';
import 'home_view_model.dart';
import 'stream_controller.dart' as stream_ctrl;

class ChatActionResult {
  final bool success;
  final String? errorMessage;
  final ChatMessage? assistantMessage;

  ChatActionResult({
    required this.success,
    this.errorMessage,
    this.assistantMessage,
  });

  factory ChatActionResult.success(ChatMessage assistantMessage) =>
      ChatActionResult(success: true, assistantMessage: assistantMessage);

  factory ChatActionResult.error(String message) =>
      ChatActionResult(success: false, errorMessage: message);

  factory ChatActionResult.noModel() =>
      ChatActionResult(success: false, errorMessage: 'no_model');
}

class ChatActions {
  ChatActions({
    required this.chatService,
    required this.chatController,
    required this.streamController,
    required this.generationController,
    required this.messageGenerationService,
    required this.contextProvider,
    required this.viewModel,
    required this.chatOrchestratorService,
  });

  final HomeViewModel viewModel;
  final ChatService chatService;
  final ChatController chatController;
  final stream_ctrl.StreamController streamController;
  final GenerationController generationController;
  final MessageGenerationService messageGenerationService;
  final BuildContext contextProvider;
  final ChatOrchestratorService chatOrchestratorService;

  VoidCallback? onMessagesChanged;
  void Function(String conversationId, bool loading)? onLoadingChanged;
  void Function(String messageId, String content, int totalTokens)?
  onContentUpdated;
  void Function(String error)? onStreamError;
  void Function(String conversationId)? onMaybeGenerateTitle;
  void Function(String conversationId)? onMaybeGenerateSummary;
  void Function(String messageId, String content, {bool immediate})?
  onScheduleImageSanitize;
  VoidCallback? onStreamFinished;
  VoidCallback? onFileProcessingStarted;
  VoidCallback? onFileProcessingFinished;

  final Map<String, Future<void>> _finishStreamingFutures =
      <String, Future<void>>{};

  List<ChatMessage> get _messages => chatController.messages;
  Map<String, int> get _versionSelections => chatController.versionSelections;
  Conversation? get _currentConversation => chatController.currentConversation;
  Set<String> get _loadingConversationIds =>
      chatController.loadingConversationIds;
  Map<String, StreamSubscription<dynamic>> get _conversationStreams =>
      chatController.conversationStreams;

  void _setConversationLoading(String conversationId, bool loading) {
    chatController.setConversationLoading(conversationId, loading);
    onLoadingChanged?.call(conversationId, loading);
  }

  bool _isReasoningModel(String providerKey, String modelId) {
    return generationController.isReasoningModel(providerKey, modelId);
  }

  bool _isReasoningEnabled(int? budget) {
    return messageGenerationService.isReasoningEnabled(budget);
  }

  bool _supportsAudioAttachmentsForProvider(
    SettingsProvider settings, {
    required String providerKey,
    required String modelId,
  }) {
    return messageGenerationService.supportsAudioAttachmentsForProvider(
      settings,
      providerKey: providerKey,
      modelId: modelId,
    );
  }

  bool _hasUnsupportedAudioAttachments({
    required List<ChatMessage> messages,
    required Conversation conversation,
    required SettingsProvider settings,
    required String providerKey,
    required String modelId,
    ChatInputData? pendingInput,
  }) {
    if (_supportsAudioAttachmentsForProvider(
      settings,
      providerKey: providerKey,
      modelId: modelId,
    )) {
      return false;
    }

    if (pendingInput != null &&
        messageGenerationService.inputContainsAudioAttachments(pendingInput)) {
      return true;
    }

    final apiMessages = messageGenerationService.messageBuilderService
        .buildApiMessages(
          messages: messages,
          versionSelections: _versionSelections,
          currentConversation: conversation,
        );
    return messageGenerationService.apiMessagesContainAudioAttachments(
      apiMessages,
    );
  }

  @visibleForTesting
  static List<ChatMessage> projectMessagesForRegenerationContext({
    required List<ChatMessage> messages,
    required int lastKeep,
    required String? targetGroupId,
  }) {
    if (lastKeep >= messages.length - 1) {
      return List<ChatMessage>.of(messages);
    }

    final keepGroups = <String>{};
    for (int i = 0; i <= lastKeep && i < messages.length; i++) {
      keepGroups.add(messages[i].groupId ?? messages[i].id);
    }
    if (targetGroupId != null) keepGroups.add(targetGroupId);

    final projected = <ChatMessage>[];
    for (int i = 0; i < messages.length; i++) {
      if (i <= lastKeep) {
        projected.add(messages[i]);
        continue;
      }
      final gid = messages[i].groupId ?? messages[i].id;
      if (keepGroups.contains(gid)) {
        projected.add(messages[i]);
      }
    }
    return projected;
  }

  @visibleForTesting
  static List<ChatMessage> buildRegenerationMessages({
    required List<ChatMessage> messages,
    required int lastKeep,
    required String? targetGroupId,
    required ChatMessage assistantPlaceholder,
  }) {
    return <ChatMessage>[
      ...projectMessagesForRegenerationContext(
        messages: messages,
        lastKeep: lastKeep,
        targetGroupId: targetGroupId,
      ),
      assistantPlaceholder,
    ];
  }

  String _transformAssistantContent(
    stream_ctrl.StreamingState state, [
    String? raw,
  ]) {
    return applyAssistantRegexes(
      raw ?? state.fullContentRaw,
      assistant: state.ctx.assistant,
      scope: AssistantRegexScope.assistant,
      target: AssistantRegexTransformTarget.persist,
    );
  }

  // ============================================================================
  // Send Message
  // ============================================================================

  Future<ChatActionResult> sendMessage({
    required ChatInputData input,
    required Conversation conversation,
  }) async {
    final content = input.text.trim();
    if (content.isEmpty &&
        input.imagePaths.isEmpty &&
        input.documents.isEmpty) {
      return ChatActionResult.error('empty_input');
    }

    final settings = contextProvider.read<SettingsProvider>();
    final assistant = contextProvider
        .read<AssistantProvider>()
        .currentAssistant;
    final assistantId = assistant?.id;
    ToolApprovalService? approvalService;
    try {
      approvalService = contextProvider.read<ToolApprovalService>();
    } catch (_) {}
    final modelConfig = messageGenerationService.getModelConfig(
      settings,
      assistant,
    );

    if (modelConfig.providerKey == null || modelConfig.modelId == null) {
      return ChatActionResult.noModel();
    }
    final providerKey = modelConfig.providerKey!;
    final modelId = modelConfig.modelId!;

    if (_hasUnsupportedAudioAttachments(
      messages: _messages,
      conversation: conversation,
      settings: settings,
      providerKey: providerKey,
      modelId: modelId,
      pendingInput: input,
    )) {
      return ChatActionResult.error('audio_attachment_unsupported');
    }

    final userMessage = await messageGenerationService.createUserMessage(
      conversationId: conversation.id,
      input: input,
      assistant: assistant,
    );
    _messages.add(userMessage);
    onMessagesChanged?.call();

    _setConversationLoading(conversation.id, true);

    final assistantMessage = await messageGenerationService
        .createAssistantPlaceholder(
          conversationId: conversation.id,
          modelId: modelId,
          providerKey: providerKey,
        );

    streamController.markStreamingStarted(assistantMessage.id);

    _messages.add(assistantMessage);
    onMessagesChanged?.call();

    streamController.toolParts.remove(assistantMessage.id);
    final supportsReasoning = _isReasoningModel(providerKey, modelId);
    final enableReasoning =
        supportsReasoning &&
        _isReasoningEnabled(
          assistant?.thinkingBudget ?? settings.thinkingBudget,
        );
    await messageGenerationService.initializeReasoningState(
      messageId: assistantMessage.id,
      enableReasoning: enableReasoning,
    );

    messageGenerationService.onFileProcessingStarted = onFileProcessingStarted;
    messageGenerationService.onFileProcessingFinished =
        onFileProcessingFinished;
    try {
      final prepared = await messageGenerationService
          .prepareApiMessagesWithInjections(
            messages: _messages,
            versionSelections: _versionSelections,
            currentConversation: conversation,
            settings: settings,
            assistant: assistant,
            assistantId: assistantId,
            providerKey: providerKey,
            modelId: modelId,
            approvalService: approvalService,
          );

      final userImagePaths = messageGenerationService.buildUserImagePaths(
        input: input,
        lastUserImagePaths: prepared.lastUserImagePaths,
        settings: settings,
        providerKey: providerKey,
        modelId: modelId,
      );

      final ctx = messageGenerationService.buildGenerationContext(
        assistantMessage: assistantMessage,
        prepared: prepared,
        userImagePaths: userImagePaths,
        providerKey: providerKey,
        modelId: modelId,
        assistant: assistant,
        settings: settings,
        supportsReasoning: supportsReasoning,
        enableReasoning: enableReasoning,
        generateTitleOnFinish: true,
      );

      await _executeGeneration(ctx);
      return ChatActionResult.success(assistantMessage);
    } catch (e) {
      onFileProcessingFinished?.call();
      return ChatActionResult.error(e.toString());
    }
  }

  // ============================================================================
  // Regenerate Message
  // ============================================================================

  Future<ChatActionResult> regenerateAtMessage({
    required ChatMessage message,
    required Conversation conversation,
    bool assistantAsNewReply = false,
  }) async {
    final settings = contextProvider.read<SettingsProvider>();
    final assistant = contextProvider
        .read<AssistantProvider>()
        .currentAssistant;
    ToolApprovalService? regenApprovalService;
    try {
      regenApprovalService = contextProvider.read<ToolApprovalService>();
    } catch (_) {}

    await cancelStreaming(conversation);

    final idx = _messages.indexWhere((m) => m.id == message.id);
    if (idx < 0) {
      return ChatActionResult.error('message_not_found');
    }

    final versioning = messageGenerationService.calculateRegenerationVersioning(
      message: message,
      messages: _messages,
      assistantAsNewReply: assistantAsNewReply,
    );
    if (versioning.lastKeep < 0) {
      return ChatActionResult.error('invalid_versioning');
    }

    final assistantId = assistant?.id;
    final modelConfig = messageGenerationService.getModelConfig(
      settings,
      assistant,
    );

    if (modelConfig.providerKey == null || modelConfig.modelId == null) {
      return ChatActionResult.noModel();
    }
    final providerKey = modelConfig.providerKey!;
    final modelId = modelConfig.modelId!;

    final projectedMessages = ChatActions.projectMessagesForRegenerationContext(
      messages: _messages,
      lastKeep: versioning.lastKeep,
      targetGroupId: versioning.targetGroupId,
    );
    if (_hasUnsupportedAudioAttachments(
      messages: projectedMessages,
      conversation: conversation,
      settings: settings,
      providerKey: providerKey,
      modelId: modelId,
    )) {
      return ChatActionResult.error('audio_attachment_unsupported');
    }

    final assistantMessage = await messageGenerationService
        .createAssistantPlaceholder(
          conversationId: conversation.id,
          modelId: modelId,
          providerKey: providerKey,
          groupId: versioning.targetGroupId,
          version: versioning.nextVersion,
        );

    streamController.markStreamingStarted(assistantMessage.id);

    final gid = assistantMessage.groupId ?? assistantMessage.id;
    _versionSelections[gid] = assistantMessage.version;
    await chatService.setSelectedVersion(
      conversation.id,
      gid,
      assistantMessage.version,
    );

    final regenerationMessages = ChatActions.buildRegenerationMessages(
      messages: _messages,
      lastKeep: versioning.lastKeep,
      targetGroupId: versioning.targetGroupId,
      assistantPlaceholder: assistantMessage,
    );

    _messages.add(assistantMessage);
    onMessagesChanged?.call();

    _setConversationLoading(conversation.id, true);

    final supportsReasoning = _isReasoningModel(providerKey, modelId);
    final enableReasoning =
        supportsReasoning &&
        _isReasoningEnabled(
          assistant?.thinkingBudget ?? settings.thinkingBudget,
        );
    await messageGenerationService.initializeReasoningState(
      messageId: assistantMessage.id,
      enableReasoning: enableReasoning,
    );

    final prepared = await messageGenerationService
        .prepareApiMessagesWithInjections(
          messages: regenerationMessages,
          versionSelections: _versionSelections,
          currentConversation: conversation,
          settings: settings,
          assistant: assistant,
          assistantId: assistantId,
          providerKey: providerKey,
          modelId: modelId,
          approvalService: regenApprovalService,
        );

    final userImagePaths = messageGenerationService.buildUserImagePaths(
      input: null,
      lastUserImagePaths: prepared.lastUserImagePaths,
      settings: settings,
      providerKey: providerKey,
      modelId: modelId,
    );

    final ctx = messageGenerationService.buildGenerationContext(
      assistantMessage: assistantMessage,
      prepared: prepared,
      userImagePaths: userImagePaths,
      providerKey: providerKey,
      modelId: modelId,
      assistant: assistant,
      settings: settings,
      supportsReasoning: supportsReasoning,
      enableReasoning: enableReasoning,
      generateTitleOnFinish: false,
    );

    await _executeGeneration(ctx);
    return ChatActionResult.success(assistantMessage);
  }

  // ============================================================================
  // Cancel Streaming
  // ============================================================================

  Future<void> cancelStreaming(Conversation? conversation) async {
    final cid = conversation?.id;
    if (cid == null) return;

    try {
      contextProvider.read<ToolApprovalService>().cancelAll();
    } catch (_) {}

    onFileProcessingFinished?.call();

    final sub = _conversationStreams.remove(cid);
    await sub?.cancel();
    ChatApiService.cancelRequest(cid);

    ChatMessage? streaming;
    for (var i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.role == 'assistant' && m.isStreaming) {
        streaming = m;
        break;
      }
    }
    if (streaming != null) {
      streamController.markStreamingEnded(streaming.id);

      await chatService.updateMessage(
        streaming.id,
        content: streaming.content,
        isStreaming: false,
        totalTokens: streaming.totalTokens,
      );

      final idx = _messages.indexWhere((m) => m.id == streaming!.id);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(isStreaming: false);
        onMessagesChanged?.call();
      }
      _setConversationLoading(cid, false);

      await streamController.finishReasoningAndPersist(
        streaming.id,
        updateReasoningInDb:
            (
              String messageId, {
              String? reasoningText,
              DateTime? reasoningFinishedAt,
              String? reasoningSegmentsJson,
            }) async {
              await chatService.updateMessage(
                messageId,
                reasoningText: reasoningText,
                reasoningFinishedAt: reasoningFinishedAt,
                reasoningSegmentsJson: reasoningSegmentsJson,
              );
            },
      );

      onScheduleImageSanitize?.call(
        streaming.id,
        streaming.content,
        immediate: true,
      );
    } else {
      _setConversationLoading(cid, false);
    }
  }

  // ============================================================================
  // Stream Execution
  // ============================================================================

  Future<void> _executeGeneration(stream_ctrl.GenerationContext ctx) async {
    final state = stream_ctrl.StreamingState(ctx);
    final assistant = ctx.assistant;
    final conversationId = state.conversationId;

    streamController.markStreamingStarted(state.messageId);

    try {
      final stream = ChatApiService.sendMessageStream(
        config: ctx.config,
        modelId: ctx.modelId,
        messages: ctx.apiMessages,
        userImagePaths: ctx.userImagePaths,
        thinkingBudget:
            assistant?.thinkingBudget ?? ctx.settings.thinkingBudget,
        temperature: assistant?.temperature,
        topP: assistant?.topP,
        maxTokens: assistant?.maxTokens,
        tools: ctx.toolDefs.isEmpty ? null : ctx.toolDefs,
        onToolCall: ctx.onToolCall,
        extraHeaders: ctx.extraHeaders,
        extraBody: ctx.extraBody,
        stream: ctx.streamOutput,
        requestId: conversationId,
      );

      await _conversationStreams[conversationId]?.cancel();
      late final StreamSubscription<ChatStreamChunk> sub;
      sub = stream.listen(
        (chunk) {
          sub.pause();
          _handleStreamChunk(chunk, state).whenComplete(() => sub.resume());
        },
        onError: (e) => _handleStreamError(e, state),
        onDone: () => _handleStreamDone(state),
        cancelOnError: true,
      );
      _conversationStreams[conversationId] = sub;
    } catch (e) {
      await _handleStreamError(e, state);
    }
  }

  // ============================================================================
  // Stream Chunk Handlers
  // ============================================================================

  Future<void> _handleStreamChunk(
    ChatStreamChunk chunk,
    stream_ctrl.StreamingState state,
  ) async {
    final chunkContent = chunk.content.isNotEmpty
        ? streamController.captureGeminiThoughtSignature(
            chunk.content,
            state.messageId,
          )
        : '';

    if ((chunk.reasoning ?? '').isNotEmpty && state.ctx.supportsReasoning) {
      await _handleReasoningChunk(chunk, state);
    }

    if ((chunk.toolCalls ?? const []).isNotEmpty) {
      await _handleToolCallsChunk(chunk, state);
    }

    if ((chunk.toolResults ?? const []).isNotEmpty) {
      await _handleToolResultsChunk(chunk, state);
    }

    if (chunk.isDone) {
      await _handleStreamFinish(chunk, state, chunkContent);
    } else {
      await _handleContentChunk(chunk, state, chunkContent);
    }
  }

  Future<void> _handleReasoningChunk(
    ChatStreamChunk chunk,
    stream_ctrl.StreamingState state,
  ) async {
    await streamController.handleReasoningChunk(
      chunk,
      state,
      updateReasoningInDb:
          (
            String messageId, {
            String? reasoningText,
            DateTime? reasoningStartAt,
            String? reasoningSegmentsJson,
          }) async {
            await chatService.updateMessageSilent(
              messageId,
              reasoningText: reasoningText,
              reasoningStartAt: reasoningStartAt,
              reasoningSegmentsJson: reasoningSegmentsJson,
            );
          },
    );
  }

  Future<void> _handleToolCallsChunk(
    ChatStreamChunk chunk,
    stream_ctrl.StreamingState state,
  ) async {
    await streamController.handleToolCallsChunk(
      chunk,
      state,
      updateReasoningSegmentsInDb: (String messageId, String json) async {
        await chatService.updateMessageSilent(
          messageId,
          reasoningSegmentsJson: json,
        );
      },
      setToolEventsInDb:
          (String messageId, List<Map<String, dynamic>> events) async {
            await chatService.setToolEvents(messageId, events);
          },
      getToolEventsFromDb: (String messageId) =>
          chatService.getToolEvents(messageId),
    );
  }

  Future<void> _handleToolResultsChunk(
    ChatStreamChunk chunk,
    stream_ctrl.StreamingState state,
  ) async {
    await streamController.handleToolResultsChunk(
      chunk,
      state,
      upsertToolEventInDb:
          (
            String messageId, {
            required String id,
            required String name,
            required Map<String, dynamic> arguments,
            String? content,
          }) async {
            await chatService.upsertToolEvent(
              messageId,
              id: id,
              name: name,
              arguments: arguments,
              content: content,
            );
          },
    );
  }

  Future<void> _handleContentChunk(
    ChatStreamChunk chunk,
    stream_ctrl.StreamingState state,
    String chunkContent,
  ) async {
    if (state.finishHandled) return;

    final messageId = state.messageId;
    final conversationId = state.conversationId;

    if (state.hadThinkingBlock && chunkContent.isNotEmpty) {
      state.contentSplitOffsets.add(state.fullContentRaw.length);
      state.reasoningCountAtSplit.add(
        streamController.getReasoningSegmentCount(messageId),
      );
      state.toolCountAtSplit.add(streamController.getToolPartsCount(messageId));
      state.hadThinkingBlock = false;
      streamController.setContentSplitData(
        messageId,
        stream_ctrl.ContentSplitData(
          offsets: List<int>.of(state.contentSplitOffsets),
          reasoningCounts: List<int>.of(state.reasoningCountAtSplit),
          toolCounts: List<int>.of(state.toolCountAtSplit),
        ),
      );
      await chatService.updateMessageSilent(
        messageId,
        reasoningSegmentsJson: streamController
            .serializeReasoningSegmentsWithSplits(
              streamController.getReasoningSegments(messageId) ?? const [],
              contentSplitOffsets: state.contentSplitOffsets,
              reasoningCountAtSplit: state.reasoningCountAtSplit,
              toolCountAtSplit: state.toolCountAtSplit,
            ),
      );
    }

    state.fullContentRaw += chunkContent;
    state.streamStartedAt ??= DateTime.now();
    if (chunk.totalTokens > 0) {
      state.totalTokens = chunk.totalTokens;
    }
    if (chunk.usage != null) {
      state.usage = (state.usage ?? const TokenUsage()).merge(chunk.usage!);
      state.totalTokens = state.usage!.totalTokens;
    }

    String streamingProcessed = _transformAssistantContent(state);
    if (streamingProcessed.contains('data:image') &&
        streamingProcessed.contains('base64,')) {
      try {
        final sanitized =
            await MarkdownMediaSanitizer.replaceInlineBase64Images(
              streamingProcessed,
            );
        if (sanitized != streamingProcessed) {
          streamingProcessed = sanitized;
          state.fullContentRaw = sanitized;
        }
      } catch (e) {}
    }

    if (state.finishHandled) return;

    onScheduleImageSanitize?.call(
      messageId,
      streamingProcessed,
      immediate: true,
    );
    await chatService.updateMessageSilent(
      messageId,
      content: streamingProcessed,
      totalTokens: state.totalTokens,
    );

    if (state.finishHandled) return;

    if (state.ctx.streamOutput && _currentConversation?.id == conversationId) {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          content: streamingProcessed,
          totalTokens: state.totalTokens,
        );
      }
    }

    if (state.ctx.streamOutput && chunkContent.isNotEmpty) {
      await _finishReasoningOnContent(state);
    }

    if (state.finishHandled) return;

    if (state.ctx.streamOutput) {
      streamController.scheduleThrottledUpdate(
        messageId,
        conversationId,
        streamingProcessed,
        totalTokens: state.totalTokens,
        contentSplitOffsets: state.contentSplitOffsets,
        reasoningCountAtSplit: state.reasoningCountAtSplit,
        toolCountAtSplit: state.toolCountAtSplit,
        promptTokens: state.usage?.promptTokens,
        completionTokens: state.usage?.completionTokens,
        cachedTokens: state.usage?.cachedTokens,
        durationMs: state.streamStartedAt != null
            ? DateTime.now().difference(state.streamStartedAt!).inMilliseconds
            : null,
        updateMessageInList: (id, content, tokens) {
          onContentUpdated?.call(id, content, tokens);
        },
      );
    }
  }

  Future<void> _finishReasoningOnContent(
    stream_ctrl.StreamingState state,
  ) async {
    await streamController.finishReasoningAndPersist(
      state.messageId,
      updateReasoningInDb:
          (
            String messageId, {
            String? reasoningText,
            DateTime? reasoningFinishedAt,
            String? reasoningSegmentsJson,
          }) async {
            await chatService.updateMessageSilent(
              messageId,
              reasoningText: reasoningText,
              reasoningFinishedAt: reasoningFinishedAt,
              reasoningSegmentsJson: reasoningSegmentsJson,
            );
          },
    );
  }

  Future<void> _handleStreamFinish(
    ChatStreamChunk chunk,
    stream_ctrl.StreamingState state,
    String chunkContent,
  ) async {
    final messageId = state.messageId;
    final conversationId = state.conversationId;
    final autoCollapseThinking =
        (!state.ctx.streamOutput && state.bufferedReasoning.isNotEmpty)
        ? contextProvider.read<SettingsProvider>().autoCollapseThinking
        : null;

    if (state.hadThinkingBlock && chunkContent.isNotEmpty) {
      state.contentSplitOffsets.add(state.fullContentRaw.length);
      state.reasoningCountAtSplit.add(
        streamController.getReasoningSegmentCount(messageId),
      );
      state.toolCountAtSplit.add(streamController.getToolPartsCount(messageId));
      state.hadThinkingBlock = false;
      streamController.setContentSplitData(
        messageId,
        stream_ctrl.ContentSplitData(
          offsets: List<int>.of(state.contentSplitOffsets),
          reasoningCounts: List<int>.of(state.reasoningCountAtSplit),
          toolCounts: List<int>.of(state.toolCountAtSplit),
        ),
      );
    }

    if (chunkContent.isNotEmpty) {
      state.fullContentRaw += chunkContent;
    }

    final hasLoadingTool =
        (streamController.toolParts[messageId]?.any((p) => p.loading) ?? false);
    if (hasLoadingTool) {
      return;
    }

    if (chunk.totalTokens > 0) {
      state.totalTokens = chunk.totalTokens;
    }
    if (chunk.usage != null) {
      state.usage = (state.usage ?? const TokenUsage()).merge(chunk.usage!);
      state.totalTokens = state.usage!.totalTokens;
    }

    final finishFuture = _finishStreaming(state);
    _finishStreamingFutures[messageId] = finishFuture;
    await finishFuture;
    _finishStreamingFutures.remove(messageId);

    onStreamFinished?.call();

    if (!state.ctx.streamOutput && state.bufferedReasoning.isNotEmpty) {
      final now = DateTime.now();
      final startAt = state.reasoningStartAt ?? now;
      await chatService.updateMessage(
        messageId,
        reasoningText: state.bufferedReasoning,
        reasoningStartAt: startAt,
        reasoningFinishedAt: now,
      );
      streamController.reasoning[messageId] = stream_ctrl.ReasoningData()
        ..text = state.bufferedReasoning
        ..startAt = startAt
        ..finishedAt = now
        ..expanded = !(autoCollapseThinking ?? false);
    }

    await _conversationStreams.remove(conversationId)?.cancel();

    final r = streamController.reasoning[messageId];
    if (r != null && r.finishedAt == null) {
      r.finishedAt = DateTime.now();
      await chatService.updateMessage(
        messageId,
        reasoningText: r.text,
        reasoningFinishedAt: r.finishedAt,
      );
    }
  }

  Future<void> _finishStreaming(
    stream_ctrl.StreamingState state, {
    bool generateTitle = true,
  }) async {
    final messageId = state.messageId;
    final conversationId = state.conversationId;

    streamController.markStreamingEnded(messageId);
    streamController.cleanupTimers(messageId);

    final shouldGenerateTitle =
        generateTitle && state.ctx.generateTitleOnFinish && !state.titleQueued;
    if (state.finishHandled) {
      if (shouldGenerateTitle) {
        state.titleQueued = true;
        onMaybeGenerateTitle?.call(conversationId);
      }
      return;
    }
    state.finishHandled = true;
    if (shouldGenerateTitle) {
      state.titleQueued = true;
    }

    final processedContent = _transformAssistantContent(state);

    final finalDurationMs = state.streamStartedAt != null
        ? DateTime.now().difference(state.streamStartedAt!).inMilliseconds
        : null;
    final finalPromptTokens = state.usage?.promptTokens;
    final finalCompletionTokens = state.usage?.completionTokens;
    final finalCachedTokens = state.usage?.cachedTokens;

    streamController.streamingContentNotifier.updateContent(
      messageId,
      processedContent,
      state.totalTokens,
      contentSplitOffsets: state.contentSplitOffsets,
      reasoningCountAtSplit: state.reasoningCountAtSplit,
      toolCountAtSplit: state.toolCountAtSplit,
      promptTokens: finalPromptTokens,
      completionTokens: finalCompletionTokens,
      cachedTokens: finalCachedTokens,
      durationMs: finalDurationMs,
    );

    final sanitizedContent =
        await MarkdownMediaSanitizer.replaceInlineBase64Images(
          processedContent,
        );
    await chatService.updateMessage(
      messageId,
      content: sanitizedContent,
      totalTokens: state.totalTokens,
      isStreaming: false,
      promptTokens: finalPromptTokens,
      completionTokens: finalCompletionTokens,
      cachedTokens: finalCachedTokens,
      durationMs: finalDurationMs,
    );

    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(
        content: sanitizedContent,
        totalTokens: state.totalTokens,
        isStreaming: false,
        promptTokens: finalPromptTokens,
        completionTokens: finalCompletionTokens,
        cachedTokens: finalCachedTokens,
        durationMs: finalDurationMs,
      );
      onMessagesChanged?.call();
    }

    streamController.removeStreamingNotifier(messageId);

    _setConversationLoading(conversationId, false);

    await streamController.finishReasoningAndPersist(
      messageId,
      updateReasoningInDb:
          (
            String messageId, {
            String? reasoningText,
            DateTime? reasoningFinishedAt,
            String? reasoningSegmentsJson,
          }) async {
            await chatService.updateMessage(
              messageId,
              reasoningText: reasoningText,
              reasoningFinishedAt: reasoningFinishedAt,
              reasoningSegmentsJson: reasoningSegmentsJson,
            );
          },
    );

    // NEW: If this conversation is a sub-task, report results back to parent
    final currentConvo = _currentConversation;
    if (currentConvo != null &&
        currentConvo.parentConversationId != null &&
        sanitizedContent.isNotEmpty) {
      try {
        await chatOrchestratorService.reportToParent(
          childConversationId: currentConvo.id,
          summary: sanitizedContent.length > 2000
              ? '${sanitizedContent.substring(0, 2000)}\n\n[Response truncated]'
              : sanitizedContent,
          taskStatus: TaskStatus.completed,
        );
      } catch (_) {}
    }

    if (shouldGenerateTitle) {
      onMaybeGenerateTitle?.call(conversationId);
    }

    onMaybeGenerateSummary?.call(conversationId);
  }

  Future<void> _handleStreamError(
    dynamic e,
    stream_ctrl.StreamingState state,
  ) async {
    final messageId = state.messageId;
    final conversationId = state.conversationId;
    final errorText = e.toString();

    onFileProcessingFinished?.call();
    streamController.markStreamingEnded(messageId);
    streamController.cleanupTimers(messageId);
    final rawContent = state.fullContentRaw.isNotEmpty
        ? state.fullContentRaw
        : errorText;
    final processed = _transformAssistantContent(state, rawContent);
    final displayContent = processed.isNotEmpty ? processed : errorText;
    await chatService.updateMessage(
      messageId,
      content: displayContent,
      totalTokens: state.totalTokens,
      isStreaming: false,
    );

    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(
        content: displayContent,
        isStreaming: false,
        totalTokens: state.totalTokens,
      );
      onMessagesChanged?.call();
    }

    streamController.removeStreamingNotifier(messageId);
    _setConversationLoading(conversationId, false);

    await streamController.finishReasoningAndPersist(
      messageId,
      updateReasoningInDb:
          (
            String messageId, {
            String? reasoningText,
            DateTime? reasoningFinishedAt,
            String? reasoningSegmentsJson,
          }) async {
            await chatService.updateMessage(
              messageId,
              reasoningText: reasoningText,
              reasoningFinishedAt: reasoningFinishedAt,
              reasoningSegmentsJson: reasoningSegmentsJson,
            );
          },
    );

    await _conversationStreams.remove(conversationId)?.cancel();
    onStreamError?.call(errorText);
    onStreamFinished?.call();
  }

  Future<void> _handleStreamDone(stream_ctrl.StreamingState state) async {
    onFileProcessingFinished?.call();

    final conversationId = state.conversationId;
    final messageId = state.messageId;

    streamController.markStreamingEnded(messageId);
    streamController.cleanupTimers(messageId);

    final inFlight = _finishStreamingFutures[messageId];
    if (inFlight != null) {
      await inFlight;
    } else if (_loadingConversationIds.contains(conversationId)) {
      await _finishStreaming(
        state,
        generateTitle: state.ctx.generateTitleOnFinish,
      );
    }
    streamController.removeStreamingNotifier(messageId);
    onStreamFinished?.call();
    await _conversationStreams.remove(conversationId)?.cancel();
  }

  Future<void> flushConversationProgress(Conversation? conversation) async {
    final cid = conversation?.id;
    if (cid == null || _messages.isEmpty) return;

    ChatMessage? streaming;
    for (var i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.role == 'assistant' && m.isStreaming && m.conversationId == cid) {
        streaming = m;
        break;
      }
    }
    if (streaming == null) return;

    String latestContent = streaming.content;
    final r = streamController.reasoning[streaming.id];
    final segs = streamController.reasoningSegments[streaming.id];

    try {
      await chatService.updateMessage(
        streaming.id,
        content: latestContent,
        totalTokens: streaming.totalTokens,
      );
      if (r != null) {
        await chatService.updateMessage(
          streaming.id,
          reasoningText: r.text,
          reasoningStartAt: r.startAt ?? DateTime.now(),
        );
      }
      if (segs != null && segs.isNotEmpty) {
        await chatService.updateMessage(
          streaming.id,
          reasoningSegmentsJson: streamController
              .serializeReasoningSegmentsWithSplits(
                segs,
                contentSplitOffsets: streamController
                    .getContentSplitData(streaming.id)
                    ?.offsets,
                reasoningCountAtSplit: streamController
                    .getContentSplitData(streaming.id)
                    ?.reasoningCounts,
                toolCountAtSplit: streamController
                    .getContentSplitData(streaming.id)
                    ?.toolCounts,
              ),
        );
      } else if (streamController.getContentSplitData(streaming.id) != null) {
        final splits = streamController.getContentSplitData(streaming.id)!;
        await chatService.updateMessage(
          streaming.id,
          reasoningSegmentsJson: streamController
              .serializeReasoningSegmentsWithSplits(
                const [],
                contentSplitOffsets: splits.offsets,
                reasoningCountAtSplit: splits.reasoningCounts,
                toolCountAtSplit: splits.toolCounts,
              ),
        );
      }
      onScheduleImageSanitize?.call(
        streaming.id,
        latestContent,
        immediate: true,
      );
    } catch (_) {}
  }
}
