import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../../core/models/assistant.dart';
import '../../../core/models/chat_input_data.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/instruction_injection.dart';
import '../../../core/models/world_book.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/memory_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/chat/document_text_extractor.dart';
import '../../../core/services/chat/prompt_transformer.dart';
import '../../../core/services/instruction_injection_store.dart';
import '../../../core/services/world_book_store.dart';
import '../../../core/services/search/search_tool_service.dart';
import '../../../core/providers/instruction_injection_provider.dart';
import '../../../core/providers/world_book_provider.dart';
import '../../../core/services/api/builtin_tools.dart';
import '../../../core/models/assistant_regex.dart';
import '../../../core/utils/multimodal_input_utils.dart';
import '../../../utils/assistant_regex.dart';
import '../../../utils/markdown_media_sanitizer.dart';

/// Service for building API messages from conversation state.
///
/// This service handles:
/// - Building API messages list from chat history
/// - Processing user messages (documents, OCR, templates)
/// - Injecting system prompts
/// - Injecting memory and recent chats context
/// - Injecting search prompts
/// - Injecting instruction prompts
/// - Injecting agent work (checklist/timer) prompts
/// - Applying context limits
/// - Inlining local images for model context
class MessageBuilderService {
  static const String internalMediaPathsKey = multimodalInternalMediaPathsKey;

  MessageBuilderService({
    required this.chatService,
    required this.contextProvider,
    this.ocrHandler,
    this.geminiThoughtSignatureHandler,
  });

  final ChatService chatService;

  /// Build context (used for accessing providers via context.read)
  final BuildContext contextProvider;

  /// OCR handler for processing images (optional, injected from home_page)
  final Future<String?> Function(List<String> imagePaths)? ocrHandler;

  /// OCR text wrapper function
  String Function(String ocrText)? ocrTextWrapper;

  /// Handler to append Gemini thought signatures for API calls
  final String Function(ChatMessage message, String content)?
  geminiThoughtSignatureHandler;

  /// Cache for document text extraction to avoid re-reading files on every message
  /// Keyed by path, validated with (modified + size) to avoid stale reuse.
  final Map<String, _DocTextCacheEntry> _docTextCache =
      <String, _DocTextCacheEntry>{};

  /// Collapse message versions to show only selected version per group.
  List<ChatMessage> collapseVersions(
    List<ChatMessage> items,
    Map<String, int> versionSelections,
  ) {
    final Map<String, List<ChatMessage>> byGroup =
        <String, List<ChatMessage>>{};
    final List<String> order = <String>[];

    for (final m in items) {
      final gid = (m.groupId ?? m.id);
      final list = byGroup.putIfAbsent(gid, () {
        order.add(gid);
        return <ChatMessage>[];
      });
      list.add(m);
    }

    // Sort each group by version
    for (final e in byGroup.entries) {
      e.value.sort((a, b) => a.version.compareTo(b.version));
    }

    // Select the appropriate version from each group
    final out = <ChatMessage>[];
    for (final gid in order) {
      final vers = byGroup[gid]!;
      final sel = versionSelections[gid];
      final idx = (sel != null && sel >= 0 && sel < vers.length)
          ? sel
          : (vers.length - 1);
      out.add(vers[idx]);
    }

    return out;
  }

  /// Build API messages list from current conversation state.
  ///
  /// Applies truncation, version collapsing, and strips [image:] / [file:] markers.
  List<Map<String, dynamic>> buildApiMessages({
    required List<ChatMessage> messages,
    required Map<String, int> versionSelections,
    required Conversation? currentConversation,
    bool includeOpenAIToolMessages = false,
  }) {
    final tIndex = currentConversation?.truncateIndex ?? -1;
    final List<ChatMessage> sourceAll =
        (tIndex >= 0 && tIndex <= messages.length)
        ? messages.sublist(tIndex)
        : List.of(messages);
    final List<ChatMessage> source = collapseVersions(
      sourceAll,
      versionSelections,
    );

    // Filter out system role messages (timer notifications, internal tracking)
    // These are never sent to the LLM as conversation history.
    final filteredSource = source.where((m) => m.role != 'system').toList();

    final out = <Map<String, dynamic>>[];

    for (final m in filteredSource) {
      // ...rest of buildApiMessages unchanged...
      var content = m.content;
      if (m.role == 'assistant' && geminiThoughtSignatureHandler != null) {
        content = geminiThoughtSignatureHandler!(m, content);
      }
      if (content.isEmpty) continue;
      final message = <String, dynamic>{
        'role': m.role == 'assistant' ? 'assistant' : 'user',
        'content': content,
      };
      out.add(message);
    }

    return out;
  }

  /// Inject agent work (checklist/timer) system prompt.
  Future<void> injectAgentWorkPrompt(
    List<Map<String, dynamic>> apiMessages,
    String? assistantId,
  ) async {
    if (assistantId == null) return;
    try {
      final ap = contextProvider.read<AssistantProvider>();
      final assistant = ap.getById(assistantId);
      if (assistant == null) return;
      if (assistant.enableMemory) {
        final buf = StringBuffer();
        buf.writeln('<active_instruction_injections>');
        buf.writeln('You have access to checklist and timer tools.');
        buf.writeln();
        buf.writeln('Rules:');
        buf.writeln('1. Use checklists to track multi-step tasks.');
        buf.writeln('2. Do not mark an item completed directly.');
        buf.writeln('3. Submit verification results instead.');
        buf.writeln('4. An item is completed only after the system records '
            'the required number of consecutive clean verification passes.');
        buf.writeln('5. When setting a timer, provide a clear prompt that '
            'can be sent back to you later.');
        buf.writeln('6. Treat shared checklists according to access permissions.');
        buf.writeln('7. When blocked, mark the item blocked and explain the blocker.');
        buf.writeln('8. Include evidence references whenever possible.');
        buf.writeln('</active_instruction_injections>');
        _appendToSystemMessage(apiMessages, buf.toString());
      }
    } catch (_) {}
  }
}