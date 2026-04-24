import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../models/conversation.dart';
import '../../models/chat_message.dart';
import '../../models/spawned_task.dart';
import '../../models/assistant.dart';
import '../../providers/settings_provider.dart';
import '../api/chat_api_service.dart';
import 'chat_service.dart';
import 'message_builder_service.dart';

/// Service for orchestrating agentic sub-tasks.
///
/// Handles spawning child conversations with task instructions,
/// executing them via API, and reporting results back to the parent.
class ChatOrchestratorService {
  ChatOrchestratorService({
    required ChatService chatService,
    required BuildContext contextProvider,
    required MessageBuilderService messageBuilderService,
  }) : _chatService = chatService,
       _contextProvider = contextProvider,
       _messageBuilderService = messageBuilderService;

  final ChatService _chatService;
  final BuildContext _contextProvider;
  final MessageBuilderService _messageBuilderService;

  /// Spawn a sub-task: create child conversation, execute the task,
  /// store the result, and report back to the parent conversation.
  Future<SpawnResult> spawnSubtask({
    required String parentConversationId,
    required String taskInstruction,
    String? title,
    String? assistantId,
    Assistant? assistant,
    String? modelProvider,
    String? modelId,
    SettingsProvider? settings,
  }) async {
    try {
      // 1. Determine model config: prefer explicit params, then assistant, then global
      final effectiveSettings = settings ??
          _contextProvider.read<SettingsProvider>();

      final effectiveProvider = modelProvider ??
          assistant?.chatModelProvider ??
          effectiveSettings.currentModelProvider;
      final effectiveModelId = modelId ??
          assistant?.chatModelId ??
          effectiveSettings.currentModelId;

      if (effectiveProvider == null || effectiveModelId == null) {
        return SpawnResult(
          success: false,
          errorMessage: 'No model configured for sub-task',
        );
      }

      // 2. Build title from instruction
      final effectiveTitle = (title?.isNotEmpty == true)
          ? title!
          : 'Sub-task: ${taskInstruction.length > 60 ? '${taskInstruction.substring(0, 57)}...' : taskInstruction}';

      // 3. Create child conversation with parent link
      final child = await _chatService.createSpawnedConversation(
        parentConversationId: parentConversationId,
        taskInstruction: taskInstruction,
        title: effectiveTitle,
        assistantId: assistantId ?? assistant?.id,
      );

      // 4. Add task instruction as user message
      await _chatService.addMessage(
        conversationId: child.id,
        role: 'user',
        content: taskInstruction,
      );

      // 5. Build API messages for the child conversation
      final childMsgs = _chatService.getMessages(child.id);
      final apiMsgs = _messageBuilderService.buildApiMessages(
        messages: childMsgs,
        versionSelections: <String, int>{},
        currentConversation: child,
      );

      // Inject system prompt if assistant is available
      _messageBuilderService.injectSystemPrompt(
        apiMsgs,
        assistant,
        effectiveModelId,
      );

      // Inject orchestration context (task instruction as system hint)
      await _injectOrchestrationContextInMessages(apiMsgs, child);

      // 6. Execute via non-streaming API call
      final cfg = effectiveSettings.getProviderConfig(effectiveProvider);
      final userPrompt = apiMsgs
          .map((m) => '${m['role']}: ${m['content']}')
          .join('\n\n');

      final response = await ChatApiService.generateText(
        config: cfg,
        modelId: effectiveModelId,
        prompt: userPrompt,
        thinkingBudget: assistant?.thinkingBudget ??
            effectiveSettings.thinkingBudget,
      );

      final trimmedResponse = response.trim();

      // 7. Store assistant response in child conversation
      await _chatService.addMessage(
        conversationId: child.id,
        role: 'assistant',
        content: trimmedResponse,
        modelId: effectiveModelId,
        providerId: effectiveProvider,
      );

      // 8. Report back to parent
      await reportToParent(
        childConversationId: child.id,
        summary: trimmedResponse.length > 2000
            ? '${trimmedResponse.substring(0, 2000)}\n\n[Response truncated]'
            : trimmedResponse,
        taskStatus: TaskStatus.completed,
      );

      return SpawnResult(
        conversation: child,
        success: true,
      );
    } catch (e) {
      return SpawnResult(
        conversation: null,
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Report a sub-task's result back to its parent conversation.
  /// Adds a structured report message to the parent's message list.
  Future<void> reportToParent({
    required String childConversationId,
    required String summary,
    required int taskStatus,
  }) async {
    final child = _chatService.getConversation(childConversationId);
    if (child == null || child.parentConversationId == null) return;

    final parentId = child.parentConversationId!;
    final parent = _chatService.getConversation(parentId);
    if (parent == null) return;

    // Update child taskStatus
    child.taskStatus = taskStatus;
    await _chatService.updateTaskStatus(childConversationId, taskStatus);

    // Build a structured report message
    final statusLabel = TaskStatus.label(taskStatus);
    final reportContent = StringBuffer();
    reportContent.writeln('## Sub-task Report');
    reportContent.writeln('**Title**: ${child.title}');
    reportContent.writeln('**Status**: $statusLabel');
    if (summary.isNotEmpty) {
      reportContent.writeln();
      reportContent.writeln('**Result**:');
      reportContent.writeln(summary);
    }
    reportContent.writeln();
    reportContent.writeln('*Sub-task ID: $childConversationId*');

    // Add report as a user-role message so the parent AI sees it in context
    await _chatService.addMessage(
      conversationId: parentId,
      role: 'user',
      content: reportContent.toString(),
      messageType: 'task_report',
    );

    // If parent was the current conversation, rebuild its message cache
    if (_chatService.currentConversationId == parentId) {
      _chatService.rebuildMessageCache(parentId);
    }
  }

  /// Update a sub-task's status.
  Future<void> updateStatus(String conversationId, int status) async {
    await _chatService.updateTaskStatus(conversationId, status);
  }

  /// Inject orchestration context into apiMessages so the child AI
  /// knows it is a sub-task.
  Future<void> _injectOrchestrationContextInMessages(
    List<Map<String, dynamic>> apiMessages,
    Conversation childConvo,
  ) async {
    if (childConvo.parentConversationId == null ||
        childConvo.taskInstruction == null ||
        childConvo.taskInstruction!.trim().isEmpty) {
      return;
    }

    final sb = StringBuffer();
    sb.writeln('## Current Task');
    sb.writeln(
      'You are working on a sub-task that was spawned by a parent conversation.',
    );
    sb.writeln(
      'Your response will be sent back to the parent as the task result.',
    );
    sb.writeln();
    sb.writeln('<task_instruction>');
    sb.writeln(childConvo.taskInstruction);
    sb.writeln('</task_instruction>');
    sb.writeln();
    sb.writeln(
      'When you complete this task, your response will be automatically reported back.',
    );

    _messageBuilderService.appendToSystemMessage(apiMessages, sb.toString());
  }
}

/// Result of a spawn sub-task operation.
class SpawnResult {
  final Conversation? conversation;
  final bool success;
  final String? errorMessage;

  SpawnResult({
    this.conversation,
    required this.success,
    this.errorMessage,
  });
}
