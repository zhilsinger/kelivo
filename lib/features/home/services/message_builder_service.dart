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

class MessageBuilderService {
  static const String internalMediaPathsKey = multimodalInternalMediaPathsKey;

  MessageBuilderService({
    required this.chatService,
    required this.contextProvider,
    this.ocrHandler,
    this.geminiThoughtSignatureHandler,
  });

  final ChatService chatService;
  final BuildContext contextProvider;
  final Future<String?> Function(List<String> imagePaths)? ocrHandler;
  String Function(String ocrText)? ocrTextWrapper;
  final String Function(ChatMessage message, String content)?
      geminiThoughtSignatureHandler;

  final Map<String, _DocTextCacheEntry> _docTextCache =
      <String, _DocTextCacheEntry>{};

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
    for (final e in byGroup.entries) {
      e.value.sort((a, b) => a.version.compareTo(b.version));
    }
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
      String? toolContinuationReasoningContent;
      if (includeOpenAIToolMessages && m.role == 'assistant') {
        final events = chatService.getToolEvents(m.id);
        if (events.isNotEmpty) {
          toolContinuationReasoningContent =
              _reasoningContentForToolContinuation(m);
          final calls = <Map<String, dynamic>>[];
          final toolMessages = <Map<String, dynamic>>[];

          for (int i = 0; i < events.length; i++) {
            final e = events[i];
            final name = (e['name'] ?? '').toString().trim();
            if (name.isEmpty) continue;
            final rawId = (e['id'] ?? '').toString().trim();
            final id = rawId.isNotEmpty
                ? rawId
                : 'call_${m.id.substring(0, m.id.length < 8 ? m.id.length : 8)}_$i';

            Map<String, dynamic> args = const <String, dynamic>{};
            final a = e['arguments'];
            if (a is Map) {
              args = a.map((k, v) => MapEntry(k.toString(), v));
            }
            String argumentsJson = '{}';
            try {
              argumentsJson = jsonEncode(args);
            } catch (_) {}

            calls.add({
              'id': id,
              'type': 'function',
              'function': {'name': name, 'arguments': argumentsJson},
            });

            final c = e['content'];
            if (c != null) {
              toolMessages.add({
                'role': 'tool',
                'name': name,
                'tool_call_id': id,
                'content': c.toString(),
              });
            }
          }

          if (calls.isNotEmpty) {
            final assistantToolMessage = <String, dynamic>{
              'role': 'assistant',
              'content': '\n\n',
              'tool_calls': calls,
            };
            if (toolContinuationReasoningContent.isNotEmpty) {
              assistantToolMessage['reasoning_content'] =
                  toolContinuationReasoningContent;
            }
            out.add(assistantToolMessage);
            out.addAll(toolMessages);
          }
        }
      }

      var content = m.content;
      if (m.role == 'assistant' && geminiThoughtSignatureHandler != null) {
        content = geminiThoughtSignatureHandler!(m, content);
      }
      if (content.isEmpty) continue;
      final message = <String, dynamic>{
        'role': m.role == 'assistant' ? 'assistant' : 'user',
        'content': content,
      };
      if (toolContinuationReasoningContent?.isNotEmpty == true) {
        message['reasoning_content'] = toolContinuationReasoningContent;
      }
      out.add(message);
    }

    return out;
  }

  ChatMessage? _latestPersistedMessage(ChatMessage message) {
    final persisted = chatService.getMessages(message.conversationId);
    for (final candidate in persisted) {
      if (candidate.id == message.id) return candidate;
    }
    return null;
  }

  String _reasoningContentForToolContinuation(ChatMessage message) {
    String pick(ChatMessage candidate) {
      final direct = (candidate.reasoningText ?? '').trim();
      if (direct.isNotEmpty) return direct;
      final raw = (candidate.reasoningSegmentsJson ?? '').trim();
      if (raw.isEmpty) return '';
      try {
        final decoded = jsonDecode(raw);
        final segmentsRaw = switch (decoded) {
          Map<String, dynamic> map => map['segments'],
          List<dynamic> list => list,
          _ => null,
        };
        if (segmentsRaw is! List) return '';
        final parts = <String>[];
        for (final item in segmentsRaw) {
          if (item is! Map) continue;
          final text = (item['text'] ?? '').toString().trim();
          if (text.isNotEmpty) parts.add(text);
        }
        return parts.join('\n').trim();
      } catch (_) {
        return '';
      }
    }
    final fromMessage = pick(message);
    if (fromMessage.isNotEmpty) return fromMessage;
    final persisted = _latestPersistedMessage(message);
    if (persisted == null) return '';
    return pick(persisted);
  }

  ChatInputData parseInputFromRaw(String raw) {
    final imgRe = RegExp(r"\[image:(.+?)\]");
    final fileRe = RegExp(r"\[file:(.+?)\|(.+?)\|(.+?)\]");
    final images = <String>[];
    final docs = <DocumentAttachment>[];
    final buffer = StringBuffer();
    int idx = 0;
    while (idx < raw.length) {
      final imgMatch = imgRe.matchAsPrefix(raw, idx);
      final fileMatch = fileRe.matchAsPrefix(raw, idx);
      if (imgMatch != null) {
        final p = imgMatch.group(1)?.trim();
        if (p != null && p.isNotEmpty) images.add(p);
        idx = imgMatch.end;
        continue;
      }
      if (fileMatch != null) {
        final path = fileMatch.group(1)?.trim() ?? '';
        final name = fileMatch.group(2)?.trim() ?? 'file';
        final mime = fileMatch.group(3)?.trim() ?? 'text/plain';
        final doc = DocumentAttachment(path: path, fileName: name, mime: mime);
        docs.add(doc);
        final effectiveMime = _effectiveAttachmentMime(doc);
        if ((isVideoMime(effectiveMime) || isAudioMime(effectiveMime)) &&
            path.isNotEmpty) {
          images.add(path);
        }
        idx = fileMatch.end;
        continue;
      }
      buffer.write(raw[idx]);
      idx++;
    }
    return ChatInputData(
      text: buffer.toString().trim(),
      imagePaths: images,
      documents: docs,
    );
  }

  String _effectiveAttachmentMime(DocumentAttachment attachment) {
    return resolveDocumentAttachmentMime(attachment);
  }

  Future<List<String>> processUserMessagesForApi(
    List<Map<String, dynamic>> apiMessages,
    SettingsProvider settings,
    Assistant? assistant,
  ) async {
    final bool ocrActive =
        settings.ocrEnabled &&
        settings.ocrModelProvider != null &&
        settings.ocrModelId != null;
    List<String>? lastUserImagePaths;
    int lastUserIdx = -1;
    for (int i = apiMessages.length - 1; i >= 0; i--) {
      if (apiMessages[i]['role'] == 'user') {
        lastUserIdx = i;
        break;
      }
    }
    Future<String?> readDocument(DocumentAttachment d) async {
      FileStat? stat;
      try {
        stat = await File(d.path).stat();
      } catch (_) {
        stat = null;
      }
      if (stat != null) {
        final cached = _docTextCache[d.path];
        if (cached != null &&
            cached.modifiedMs == stat.modified.millisecondsSinceEpoch &&
            cached.size == stat.size) {
          return cached.text;
        }
      }
      try {
        final text = await DocumentTextExtractor.extract(
          path: d.path,
          mime: d.mime,
        );
        if (stat != null) {
          _docTextCache[d.path] = _DocTextCacheEntry(
            text: text,
            modifiedMs: stat.modified.millisecondsSinceEpoch,
            size: stat.size,
          );
        }
        return text;
      } catch (_) {
        if (stat != null) {
          _docTextCache[d.path] = _DocTextCacheEntry(
            text: null,
            modifiedMs: stat.modified.millisecondsSinceEpoch,
            size: stat.size,
          );
        }
        return null;
      }
    }
    for (int i = 0; i < apiMessages.length; i++) {
      if (apiMessages[i]['role'] != 'user') continue;
      final rawUser = (apiMessages[i]['content'] ?? '').toString();
      final parsedUser = parseInputFromRaw(rawUser);
      final videoPaths = <String>{
        for (final d in parsedUser.documents)
          if (isVideoMime(_effectiveAttachmentMime(d))) d.path.trim(),
      }..removeWhere((p) => p.isEmpty);
      final audioPaths = <String>{
        for (final d in parsedUser.documents)
          if (isAudioMime(_effectiveAttachmentMime(d))) d.path.trim(),
      }..removeWhere((p) => p.isEmpty);
      final messageMediaPaths = parsedUser.imagePaths
          .map((p) => p.trim())
          .where(
            (p) =>
                p.isNotEmpty &&
                (!ocrActive ||
                    videoPaths.contains(p) ||
                    audioPaths.contains(p)),
          )
          .toSet()
          .toList(growable: false);
      if (messageMediaPaths.isEmpty) {
        apiMessages[i].remove(internalMediaPathsKey);
      } else {
        apiMessages[i][internalMediaPathsKey] = messageMediaPaths;
      }
      if (i == lastUserIdx &&
          lastUserImagePaths == null &&
          parsedUser.imagePaths.isNotEmpty) {
        lastUserImagePaths = List<String>.of(parsedUser.imagePaths);
      }
      final inlineImagePaths = parsedUser.imagePaths
          .map((p) => p.trim())
          .where(
            (p) =>
                p.isNotEmpty &&
                !videoPaths.contains(p) &&
                !audioPaths.contains(p),
          )
          .toList(growable: false);
      final replacedUserText = applyAssistantRegexes(
        parsedUser.text,
        assistant: assistant,
        scope: AssistantRegexScope.user,
        target: AssistantRegexTransformTarget.send,
      );
      final imageMarkers = (!ocrActive && inlineImagePaths.isNotEmpty)
          ? inlineImagePaths.map((p) => '\n[image:$p]').join()
          : '';
      final cleanedUser = (replacedUserText + imageMarkers).trim();
      final filePrompts = StringBuffer();
      for (final d in parsedUser.documents) {
        final effectiveMime = _effectiveAttachmentMime(d);
        if (isVideoMime(effectiveMime) || isAudioMime(effectiveMime)) {
          continue;
        }
        final text = await readDocument(d);
        if (text == null || text.trim().isEmpty) continue;
        filePrompts.writeln('## user sent a file: ${d.fileName}');
        filePrompts.writeln('<content>');
        filePrompts.writeln('```');
        filePrompts.writeln(text);
        filePrompts.writeln('```');
        filePrompts.writeln('</content>');
        filePrompts.writeln();
      }
      String merged = (filePrompts.toString() + cleanedUser).trim();
      if (ocrActive && ocrHandler != null) {
        final ocrTargets = parsedUser.imagePaths
            .map((p) => p.trim())
            .where(
              (p) =>
                  p.isNotEmpty &&
                  !videoPaths.contains(p) &&
                  !audioPaths.contains(p),
            )
            .toSet()
            .toList();
        if (ocrTargets.isNotEmpty) {
          final ocrText = await ocrHandler!(ocrTargets);
          if (ocrText != null && ocrText.trim().isNotEmpty) {
            final wrapped = ocrTextWrapper != null
                ? ocrTextWrapper!(ocrText)
                : _defaultWrapOcrBlock(ocrText);
            merged = (wrapped + merged).trim();
          }
        }
      }
      apiMessages[i]['content'] = merged.isEmpty ? cleanedUser : merged;
    }
    if (lastUserIdx != -1) {
      final userText = (apiMessages[lastUserIdx]['content'] ?? '').toString();
      final templ =
          (assistant?.messageTemplate ?? '{{ message }}').trim().isEmpty
          ? '{{ message }}'
          : (assistant!.messageTemplate);
      final templated = PromptTransformer.applyMessageTemplate(
        templ,
        role: 'user',
        message: userText,
        now: DateTime.now(),
      );
      apiMessages[lastUserIdx]['content'] = templated;
    }
    return lastUserImagePaths ?? <String>[];
  }

  String _defaultWrapOcrBlock(String ocrText) {
    final buf = StringBuffer();
    buf.writeln(
      "The image_file_ocr tag contains a description of an image that the user uploaded to you, not the user's prompt.",
    );
    buf.writeln('<image_file_ocr>');
    buf.writeln(ocrText.trim());
    buf.writeln('</image_file_ocr>');
    buf.writeln();
    return buf.toString();
  }

  void injectSystemPrompt(
    List<Map<String, dynamic>> apiMessages,
    Assistant? assistant,
    String modelId,
  ) {
    if ((assistant?.systemPrompt.trim().isNotEmpty ?? false)) {
      final vars = PromptTransformer.buildPlaceholders(
        context: contextProvider,
        assistant: assistant!,
        modelId: modelId,
        modelName: modelId,
        userNickname: contextProvider.read<UserProvider>().name,
      );
      final sys = PromptTransformer.replacePlaceholders(
        assistant.systemPrompt,
        vars,
      );
      apiMessages.insert(0, {'role': 'system', 'content': sys});
    }
  }

  Future<void> injectMemoryAndRecentChats(
    List<Map<String, dynamic>> apiMessages,
    Assistant? assistant, {
    String? currentConversationId,
  }) async {
    try {
      if (assistant?.enableMemory == true) {
        final mp = contextProvider.read<MemoryProvider>();
        await mp.initialize();
        final mems = mp.getForAssistant(assistant!.id);
        final buf = StringBuffer();
        buf.writeln('## Memories');
        buf.writeln(
          'These are memories that you can reference in the future conversations.',
        );
        buf.writeln('<memories>');
        for (final m in mems) {
          buf.writeln('<record>');
          buf.writeln('<id>${m.id}</id>');
          buf.writeln('<content>${m.content}</content>');
          buf.writeln('</record>');
        }
        buf.writeln('</memories>');
        buf.writeln('''
## Memory Tool
\u4f60\u662f\u4e00\u4e2a\u65e0\u72b6\u6001\u7684\u5927\u6a21\u578b\uff0c\u4f60\u65e0\u6cd5\u5b58\u50a8\u8bb0\u5fc6\uff0c\u56e0\u6b64\u4e3a\u4e86\u8bb0\u4f4f\u4fe1\u606f\uff0c\u4f60\u9700\u8981\u4f7f\u7528**\u8bb0\u5fc6\u5de5\u5177**\u3002
\u4f60\u53ef\u4ee5\u4f7f\u7528 `create_memory`, `edit_memory`, `delete_memory` \u5de5\u5177\u521b\u5efa\u3001\u66f4\u65b0\u6216\u5220\u9664\u8bb0\u5fc6\u3002
- \u5982\u679c\u8bb0\u5fc6\u4e2d\u6ca1\u6709\u76f8\u5173\u4fe1\u606f\uff0c\u8bf7\u4f7f\u7528 create_memory \u521b\u5efa\u4e00\u6761\u65b0\u7684\u8bb0\u5f55\u3002
- \u5982\u679c\u5df2\u6709\u76f8\u5173\u8bb0\u5f55\uff0c\u8bf7\u4f7f\u7528 edit_memory \u66f4\u65b0\u5185\u5bb9\u3002
- \u82e5\u8bb0\u5fc6\u8fc7\u65f6\u6216\u65e0\u7528\uff0c\u8bf7\u4f7f\u7528 delete_memory \u5220\u9664\u3002
\u8fd9\u4e9b\u8bb0\u5fc6\u4f1a\u81ea\u52a8\u5305\u542b\u5728\u672a\u6765\u7684\u5bf9\u8bdd\u4e0a\u4e0b\u6587\u4e2d\uff0c\u5728<memories>\u6807\u7b7e\u5185\u3002
\u8bf7\u52ff\u5728\u8bb0\u5fc6\u4e2d\u5b58\u50a8\u654f\u611f\u4fe1\u606f\uff0c\u654f\u611f\u4fe1\u606f\u5305\u62ec\uff1a\u7528\u6237\u7684\u6c11\u65cf\u3001\u5b97\u6559\u4fe1\u4ef0\u3001\u6027\u53d6\u5411\u3001\u653f\u6cbb\u89c2\u70b9\u53ca\u515a\u6d3e\u5f52\u5c5e\u3001\u6027\u751f\u6d3b\u3001\u72af\u7f6a\u8bb0\u5f55\u7b49\u3002
\u5728\u4e0e\u7528\u6237\u804a\u5929\u8fc7\u7a0b\u4e2d\uff0c\u4f60\u53ef\u4ee5\u50cf\u4e00\u4e2a\u79c1\u4eba\u79d8\u4e66\u4e00\u6837**\u4e3b\u52a8\u7684**\u8bb0\u5f55\u7528\u6237\u76f8\u5173\u7684\u4fe1\u606f\u5230\u8bb0\u5fc6\u91cc\uff0c\u5305\u62ec\u4f46\u4e0d\u9650\u4e8e\uff1a
- \u7528\u6237\u6635\u79f0/\u59d3\u540d
- \u5e74\u9f84/\u6027\u522b/\u5174\u8da3\u7231\u597d
- \u8ba1\u5212\u4e8b\u9879\u7b49
- \u804a\u5929\u98ce\u683c\u504f\u597d
- \u5de5\u4f5c\u76f8\u5173
- \u9996\u6b21\u804a\u5929\u65f6\u95f4
- ...
\u8bf7\u4e3b\u52a8\u8c03\u7528\u5de5\u5177\u8bb0\u5f55\uff0c\u800c\u4e0d\u662f\u9700\u8981\u7528\u6237\u8981\u6c42\u3002
\u8bb0\u5fc6\u5982\u679c\u5305\u542b\u65e5\u671f\u4fe1\u606f\uff0c\u8bf7\u5305\u542b\u5728\u5185\uff0c\u8bf7\u4f7f\u7528\u7edd\u5bf9\u65f6\u95f4\u683c\u5f0f\uff0c\u5e76\u4e14\u5f53\u524d\u65f6\u95f4\u662f ${DateTime.now().toIso8601String()}\u3002
\u65e0\u9700\u544a\u77e5\u7528\u6237\u4f60\u5df2\u66f4\u6539\u8bb0\u5fc6\u8bb0\u5f55\uff0c\u4e5f\u4e0d\u8981\u5728\u5bf9\u8bdd\u4e2d\u76f4\u63a5\u663e\u793a\u8bb0\u5fc6\u5185\u5bb9\uff0c\u9664\u975e\u7528\u6237\u4e3b\u52a8\u8981\u6c42\u3002
\u76f8\u4f3c\u6216\u76f8\u5173\u7684\u8bb0\u5fc6\u5e94\u5408\u5e76\u4e3a\u4e00\u6761\u8bb0\u5f55\uff0c\u800c\u4e0d\u8981\u91cd\u590d\u8bb0\u5f55\uff0c\u8fc7\u65f6\u8bb0\u5f55\u5e94\u5220\u9664\u3002
\u4f60\u53ef\u4ee5\u5728\u548c\u7528\u6237\u95f2\u804a\u7684\u65f6\u5019\u6697\u793a\u7528\u6237\u4f60\u80fd\u8bb0\u4f4f\u4e1c\u897f\u3002
''');
        _appendToSystemMessage(apiMessages, buf.toString());
      }
      if (assistant?.enableRecentChatsReference == true) {
        final chats = chatService.getAllConversations();
        final relevantChats = chats
            .where(
              (c) =>
                  c.assistantId == assistant!.id &&
                  c.id != currentConversationId,
            )
            .where((c) => c.title.trim().isNotEmpty)
            .take(10)
            .toList();
        if (relevantChats.isNotEmpty) {
          final sb = StringBuffer();
          sb.writeln('<recent_chats>');
          sb.writeln('\u8fd9\u662f\u7528\u6237\u6700\u8fd1\u7684\u4e00\u4e9b\u5bf9\u8bdd\u6807\u9898\u548c\u6458\u8981\uff0c\u4f60\u53ef\u4ee5\u53c2\u8003\u8fd9\u4e9b\u5185\u5bb9\u4e86\u89e3\u7528\u6237\u504f\u597d\u548c\u5173\u6ce8\u70b9');
          for (final c in relevantChats) {
            sb.writeln('<conversation>');
            final timestamp = c.updatedAt.toIso8601String().substring(0, 10);
            final title = c.title.trim();
            final summary = (c.summary ?? '').trim();
            if (summary.isNotEmpty) {
              sb.writeln('  $timestamp: $title || $summary');
            } else {
              sb.writeln('  $timestamp: $title');
            }
            sb.writeln('</conversation>');
          }
          sb.writeln('</recent_chats>');
          _appendToSystemMessage(apiMessages, sb.toString());
        }
      }
    } catch (_) {}
  }

  void injectSearchPrompt(
    List<Map<String, dynamic>> apiMessages,
    SettingsProvider settings,
    bool hasBuiltInSearch,
  ) {
    if (settings.searchEnabled && !hasBuiltInSearch) {
      final prompt = SearchToolService.getSystemPrompt();
      _appendToSystemMessage(apiMessages, prompt);
    }
  }

  Future<void> injectInstructionPrompts(
    List<Map<String, dynamic>> apiMessages,
    String? assistantId,
  ) async {
    try {
      List<InstructionInjection> actives = const <InstructionInjection>[];
      try {
        final ip = contextProvider.read<InstructionInjectionProvider>();
        actives = ip.activesFor(assistantId);
        if (actives.isEmpty) {
          actives = await InstructionInjectionStore.getActives(
            assistantId: assistantId,
          );
        }
      } catch (_) {
        actives = await InstructionInjectionStore.getActives(
          assistantId: assistantId,
        );
      }
      final prompts = actives
          .map((e) => e.prompt.trim())
          .where((p) => p.isNotEmpty)
          .toList(growable: false);
      if (prompts.isNotEmpty) {
        final lp = prompts.join('\n\n');
        _appendToSystemMessage(apiMessages, lp);
      }
    } catch (_) {}
  }

  /// Inject agent work (checklist/timer) system prompt for assistants
  /// that have memory/agent-work capabilities enabled.
  Future<void> injectAgentWorkPrompt(
    List<Map<String, dynamic>> apiMessages,
    String? assistantId,
  ) async {
    if (assistantId == null) return;
    try {
      final ap = contextProvider.read<AssistantProvider>();
      final assistant = ap.getById(assistantId);
      if (assistant == null) return;
      // Agent work prompts are injected when memory (agent capability flag) is enabled
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

  Future<void> injectWorldBookPrompts(
    List<Map<String, dynamic>> apiMessages,
    String? assistantId,
  ) async {
    try {
      List<WorldBook> all = const <WorldBook>[];
      List<String> activeBookIds = const <String>[];

      try {
        final wb = contextProvider.read<WorldBookProvider>();
        all = wb.books;
        activeBookIds = wb.activeBookIdsFor(assistantId);
        if (all.isEmpty) all = await WorldBookStore.getAll();
        if (activeBookIds.isEmpty) {
          activeBookIds = await WorldBookStore.getActiveIds(
            assistantId: assistantId,
          );
        }
      } catch (_) {
        all = await WorldBookStore.getAll();
        activeBookIds = await WorldBookStore.getActiveIds(
          assistantId: assistantId,
        );
      }

      if (all.isEmpty || activeBookIds.isEmpty) return;

      final activeSet = activeBookIds.toSet();
      final books = all
          .where((b) => b.enabled && activeSet.contains(b.id))
          .toList(growable: false);
      if (books.isEmpty) return;

      String extractContextForDepth(int scanDepth) {
        final depth = scanDepth <= 0 ? 1 : scanDepth;
        final parts = <String>[];
        for (
          int i = apiMessages.length - 1;
          i >= 0 && parts.length < depth;
          i--
        ) {
          final role = (apiMessages[i]['role'] ?? '').toString();
          if (role != 'user' && role != 'assistant') continue;
          final content = (apiMessages[i]['content'] ?? '').toString().trim();
          if (content.isEmpty) continue;
          parts.add(content);
        }
        return parts.reversed.join('\n');
      }

      bool isTriggered(WorldBookEntry entry, String context) {
        if (!entry.enabled) return false;
        if (entry.constantActive) return true;
        if (entry.keywords.isEmpty) return false;
        for (final raw in entry.keywords) {
          final keyword = raw.trim();
          if (keyword.isEmpty) continue;
          if (entry.useRegex) {
            try {
              final re = RegExp(keyword, caseSensitive: entry.caseSensitive);
              if (re.hasMatch(context)) return true;
            } catch (_) {}
          } else {
            if (entry.caseSensitive) {
              if (context.contains(keyword)) return true;
            } else {
              if (context.toLowerCase().contains(keyword.toLowerCase())) {
                return true;
              }
            }
          }
        }
        return false;
      }

      final contextCache = <int, String>{};
      final triggered = <({WorldBookEntry entry, int seq})>[];
      int seq = 0;

      for (final book in books) {
        for (final entry in book.entries) {
          final depth = (entry.scanDepth <= 0 ? 1 : entry.scanDepth)
              .clamp(1, 200)
              .toInt();
          final ctx = contextCache.putIfAbsent(
            depth,
            () => extractContextForDepth(depth),
          );
          if (isTriggered(entry, ctx)) {
            triggered.add((entry: entry, seq: seq));
          }
          seq++;
        }
      }

      if (triggered.isEmpty) return;

      triggered.sort((a, b) {
        final pa = a.entry.priority;
        final pb = b.entry.priority;
        if (pb != pa) return pb.compareTo(pa);
        return a.seq.compareTo(b.seq);
      });

      String wrapSystemTag(String content) => '<system>\n$content\n</system>';

      String joinContents(Iterable<WorldBookEntry> items) {
        return items
            .map((e) => e.content.trim())
            .where((c) => c.isNotEmpty)
            .join('\n');
      }

      List<Map<String, dynamic>> createMergedInjectionMessages(
        List<WorldBookEntry> injections,
      ) {
        final byRole = <WorldBookInjectionRole, List<WorldBookEntry>>{};
        for (final e in injections) {
          if (e.content.trim().isEmpty) continue;
          byRole.putIfAbsent(e.role, () => <WorldBookEntry>[]).add(e);
        }
        final result = <Map<String, dynamic>>[];
        for (final role in byRole.keys) {
          final group = byRole[role]!;
          final merged = joinContents(group);
          if (merged.isEmpty) continue;
          if (role == WorldBookInjectionRole.assistant) {
            result.add({'role': 'assistant', 'content': merged});
          } else {
            result.add({'role': 'user', 'content': wrapSystemTag(merged)});
          }
        }
        return result;
      }

      int findSafeInsertIndex(List<Map<String, dynamic>> messages, int target) {
        var index = target.clamp(0, messages.length);
        while (index > 0 && index < messages.length) {
          final role = (messages[index]['role'] ?? '').toString();
          if (role != 'tool') break;
          index--;
        }
        return index;
      }

      final byPosition = <WorldBookInjectionPosition, List<WorldBookEntry>>{};
      for (final t in triggered) {
        byPosition
            .putIfAbsent(t.entry.position, () => <WorldBookEntry>[])
            .add(t.entry);
      }

      final beforeContent = joinContents(
        byPosition[WorldBookInjectionPosition.beforeSystemPrompt] ??
            const <WorldBookEntry>[],
      );
      final afterContent = joinContents(
        byPosition[WorldBookInjectionPosition.afterSystemPrompt] ??
            const <WorldBookEntry>[],
      );

      if (beforeContent.isNotEmpty || afterContent.isNotEmpty) {
        final systemIndex = apiMessages.indexWhere(
          (m) => (m['role'] ?? '').toString() == 'system',
        );
        if (systemIndex >= 0) {
          final original = (apiMessages[systemIndex]['content'] ?? '')
              .toString();
          final sb = StringBuffer();
          if (beforeContent.isNotEmpty) {
            sb.write(beforeContent);
            sb.write('\n');
          }
          sb.write(original);
          if (afterContent.isNotEmpty) {
            sb.write('\n');
            sb.write(afterContent);
          }
          apiMessages[systemIndex]['content'] = sb.toString();
        } else {
          final sb = StringBuffer();
          if (beforeContent.isNotEmpty) sb.write(beforeContent);
          if (afterContent.isNotEmpty) {
            if (sb.isNotEmpty) sb.write('\n');
            sb.write(afterContent);
          }
          if (sb.isNotEmpty) {
            apiMessages.insert(0, {'role': 'system', 'content': sb.toString()});
          }
        }
      }

      final topInjections = byPosition[WorldBookInjectionPosition.topOfChat];
      if (topInjections != null && topInjections.isNotEmpty) {
        var insertIndex = apiMessages.indexWhere(
          (m) => (m['role'] ?? '').toString() == 'user',
        );
        if (insertIndex < 0) insertIndex = apiMessages.length;
        insertIndex = findSafeInsertIndex(apiMessages, insertIndex);
        apiMessages.insertAll(
          insertIndex,
          createMergedInjectionMessages(topInjections),
        );
      }

      final bottomInjections =
          byPosition[WorldBookInjectionPosition.bottomOfChat];
      if (bottomInjections != null && bottomInjections.isNotEmpty) {
        var insertIndex = apiMessages.isEmpty ? 0 : (apiMessages.length - 1);
        insertIndex = findSafeInsertIndex(apiMessages, insertIndex);
        apiMessages.insertAll(
          insertIndex,
          createMergedInjectionMessages(bottomInjections),
        );
      }

      final atDepthInjections = byPosition[WorldBookInjectionPosition.atDepth];
      if (atDepthInjections != null && atDepthInjections.isNotEmpty) {
        final byDepth = <int, List<WorldBookEntry>>{};
        for (final e in atDepthInjections) {
          final depth = (e.injectDepth <= 0 ? 1 : e.injectDepth)
              .clamp(1, 200)
              .toInt();
          byDepth.putIfAbsent(depth, () => <WorldBookEntry>[]).add(e);
        }
        final depths = byDepth.keys.toList(growable: false)
          ..sort((a, b) => b.compareTo(a));
        for (final depth in depths) {
          final injections = byDepth[depth] ?? const <WorldBookEntry>[];
          var insertIndex = (apiMessages.length - depth).clamp(
            0,
            apiMessages.length,
          );
          insertIndex = findSafeInsertIndex(apiMessages, insertIndex);
          apiMessages.insertAll(
            insertIndex,
            createMergedInjectionMessages(injections),
          );
        }
      }
    } catch (_) {}
  }

  void _appendToSystemMessage(
    List<Map<String, dynamic>> apiMessages,
    String content,
  ) {
    if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
      apiMessages[0]['content'] =
          '${(apiMessages[0]['content'] ?? '') as String}\n\n$content';
    } else {
      apiMessages.insert(0, {'role': 'system', 'content': content});
    }
  }

  void applyContextLimit(
    List<Map<String, dynamic>> apiMessages,
    Assistant? assistant,
  ) {
    if ((assistant?.limitContextMessages ?? true) &&
        (assistant?.contextMessageSize ?? 0) > 0) {
      final int keep = (assistant!.contextMessageSize).clamp(
        Assistant.minContextMessageSize,
        Assistant.maxContextMessageSize,
      );
      int startIdx = 0;
      if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
        startIdx = 1;
      }
      final tail = apiMessages.sublist(startIdx);
      if (tail.length > keep) {
        final trimmed = tail.sublist(tail.length - keep);
        apiMessages
          ..removeRange(startIdx, apiMessages.length)
          ..addAll(trimmed);
      }
      while (apiMessages.length > startIdx &&
          (apiMessages[startIdx]['role'] ?? '').toString() == 'tool') {
        apiMessages.removeAt(startIdx);
      }
    }
  }

  Future<void> inlineLocalImages(List<Map<String, dynamic>> apiMessages) async {
    for (int i = 0; i < apiMessages.length; i++) {
      final s = (apiMessages[i]['content'] ?? '').toString();
      if (s.isNotEmpty) {
        apiMessages[i]['content'] =
            await MarkdownMediaSanitizer.inlineLocalImagesToBase64(s);
      }
    }
  }

  bool hasBuiltInSearch(
    SettingsProvider settings,
    String providerKey,
    String modelId,
  ) {
    try {
      final cfg = settings.getProviderConfig(providerKey);
      return BuiltInToolsHelper.isBuiltInSearchEnabled(
        cfg: cfg,
        modelId: modelId,
      );
    } catch (_) {
      return false;
    }
  }
}

class _DocTextCacheEntry {
  const _DocTextCacheEntry({
    required this.text,
    required this.modifiedMs,
    required this.size,
  });

  final String? text;
  final int modifiedMs;
  final int size;
}
