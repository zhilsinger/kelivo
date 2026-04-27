import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import '../../models/agent_checklist.dart';
import '../../models/agent_checklist_item.dart';
import '../../models/agent_check_result.dart';
import '../../models/agent_audit_event.dart';
import '../../models/agent_timer_job.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../../utils/app_directories.dart';

class ChatService extends ChangeNotifier {
  static const String _conversationsBoxName = 'conversations';
  static const String _messagesBoxName = 'messages';
  static const String _toolEventsBoxName = 'tool_events_v1';
  static const String _activeStreamingKey = '_active_streaming_ids';

  late Box<Conversation> _conversationsBox;
  late Box<ChatMessage> _messagesBox;
  late Box
  _toolEventsBox; // key: assistantMessageId, value: List<Map<String,dynamic>>
  String _sigKey(String id) => 'sig_$id';

  String? _currentConversationId;
  final Map<String, List<ChatMessage>> _messagesCache = {};
  final Map<String, Conversation> _draftConversations = {};

  // Localized default title for new conversations; set by UI on startup.
  String _defaultConversationTitle = 'New Chat';
  void setDefaultConversationTitle(String title) {
    if (title.trim().isEmpty) return;
    _defaultConversationTitle = title.trim();
  }

  bool _initialized = false;
  bool get initialized => _initialized;

  String? get currentConversationId => _currentConversationId;

  Future<void> init() async {
    if (_initialized) return;

    // Initialize Hive with platform-specific directory
    final appDataDir = await AppDirectories.getAppDataDirectory();
    await Hive.initFlutter(appDataDir.path);

    // Register adapters if not already registered
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ChatMessageAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ConversationAdapter());
    }
    if (!Hive.isAdapterRegistered(20)) {
      Hive.registerAdapter(ChecklistOwnerTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(21)) {
      Hive.registerAdapter(ChecklistVisibilityAdapter());
    }
    if (!Hive.isAdapterRegistered(22)) {
      Hive.registerAdapter(DoubleCheckModeAdapter());
    }
    if (!Hive.isAdapterRegistered(23)) {
      Hive.registerAdapter(ChecklistPermissionAdapter());
    }
    if (!Hive.isAdapterRegistered(24)) {
      Hive.registerAdapter(ChecklistAccessGrantAdapter());
    }
    if (!Hive.isAdapterRegistered(25)) {
      Hive.registerAdapter(AgentChecklistAdapter());
    }
    if (!Hive.isAdapterRegistered(26)) {
      Hive.registerAdapter(ChecklistItemStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(27)) {
      Hive.registerAdapter(AgentChecklistItemAdapter());
    }
    if (!Hive.isAdapterRegistered(28)) {
      Hive.registerAdapter(AgentCheckResultAdapter());
    }
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(AgentAuditEventAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(TimerStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(31)) {
      Hive.registerAdapter(AgentTimerJobAdapter());
    }

    _conversationsBox = await Hive.openBox<Conversation>(_conversationsBoxName);
    _messagesBox = await Hive.openBox<ChatMessage>(_messagesBoxName);
    _toolEventsBox = await Hive.openBox(_toolEventsBoxName);

    // Migrate any persisted message content that references old iOS sandbox paths
    await _migrateSandboxPaths();

    // Reset any stale isStreaming flags left over from a previous app crash or
    // force-quit.  After a fresh launch no message can be actively streaming.
    await _resetStaleStreamingFlags();

    _initialized = true;
    notifyListeners();
  }

  List<Conversation> getAllConversations() {
    if (!_initialized) return [];
    final conversations = _conversationsBox.values.toList();
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  List<Conversation> getPinnedConversations() {
    return getAllConversations().where((c) => c.isPinned).toList();
  }

  Conversation? getConversation(String id) {
    if (!_initialized) return null;
    return _conversationsBox.get(id) ?? _draftConversations[id];
  }

  List<ChatMessage> getMessages(String conversationId) {
    if (!_initialized) return [];

    // Check cache first
    if (_messagesCache.containsKey(conversationId)) {
      return _messagesCache[conversationId]!;
    }

    // Load from storage
    final conversation = _conversationsBox.get(conversationId);
    if (conversation == null) return [];

    final messages = <ChatMessage>[];
    for (final messageId in conversation.messageIds) {
      final message = _messagesBox.get(messageId);
      if (message != null) {
        messages.add(message);
      }
    }

    // Cache the result
    _messagesCache[conversationId] = messages;
    return messages;
  }

  Future<Conversation> createConversation({
    String? title,
    String? assistantId,
  }) async {
    if (!_initialized) await init();

    final conversation = Conversation(
      title: title ?? _defaultConversationTitle,
      assistantId: assistantId,
    );

    await _conversationsBox.put(conversation.id, conversation);
    _currentConversationId = conversation.id;
    notifyListeners();
    return conversation;
  }

  // Create a draft conversation that is not persisted until first message arrives.
  Future<Conversation> createDraftConversation({
    String? title,
    String? assistantId,
  }) async {
    if (!_initialized) await init();
    final conversation = Conversation(
      title: title ?? _defaultConversationTitle,
      assistantId: assistantId,
    );
    _draftConversations[conversation.id] = conversation;
    _currentConversationId = conversation.id;
    notifyListeners();
    return conversation;
  }

  Future<void> deleteConversation(String id) async {
    if (!_initialized) return;

    // If it's a draft and never persisted, just drop it.
    if (_draftConversations.containsKey(id)) {
      _draftConversations.remove(id);
      if (_currentConversationId == id) {
        _currentConversationId = null;
      }
      notifyListeners();
      return;
    }

    final conversation = _conversationsBox.get(id);
    if (conversation == null) return;

    // Collect local file paths referenced by messages in this conversation
    final Set<String> pathsToMaybeDelete = <String>{};
    for (final messageId in conversation.messageIds) {
      final message = _messagesBox.get(messageId);
      if (message == null) continue;
      final content = message.content;
      // [image:/abs/path]
      final imgRe = RegExp(r"\[image:(.+?)\]");
      for (final m in imgRe.allMatches(content)) {
        final pth = m.group(1)?.trim();
        if (pth != null &&
            pth.isNotEmpty &&
            !pth.startsWith('http') &&
            !pth.startsWith('data:')) {
          pathsToMaybeDelete.add(pth);
        }
      }
      // [file:/abs/path|filename|mime]
      final fileRe = RegExp(r"\[file:(.+?)\|(.+?)\|(.+?)\]");
      for (final m in fileRe.allMatches(content)) {
        final pth = m.group(1)?.trim();
        if (pth != null &&
            pth.isNotEmpty &&
            !pth.startsWith('http') &&
            !pth.startsWith('data:')) {
          pathsToMaybeDelete.add(pth);
        }
      }
    }

    // Delete all messages
    for (final messageId in conversation.messageIds) {
      final msg = _messagesBox.get(messageId);
      if (msg != null && msg.role == 'assistant') {
        try {
          await _toolEventsBox.delete(msg.id);
        } catch (_) {}
        try {
          await _toolEventsBox.delete(_sigKey(msg.id));
        } catch (_) {}
      }
      await _messagesBox.delete(messageId);
    }

    // Delete conversation
    await _conversationsBox.delete(id);

    // Remove cached messages
    // Clear cache
    _messagesCache.remove(id);

    // Delete orphaned files (not referenced by any remaining conversation)
    await _cleanupOrphanUploads();

    if (_currentConversationId == id) {
      _currentConversationId = null;
    }

    notifyListeners();
  }

  Set<String> _extractAttachmentPaths(String content) {
    final out = <String>{};
    final imgRe = RegExp(r"\[image:(.+?)\]");
    for (final m in imgRe.allMatches(content)) {
      final pth = m.group(1)?.trim();
      if (pth != null &&
          pth.isNotEmpty &&
          !pth.startsWith('http') &&
          !pth.startsWith('data:')) {
        out.add(SandboxPathResolver.fix(pth));
      }
    }
    final fileRe = RegExp(r"\[file:(.+?)\|(.+?)\|(.+?)\]");
    for (final m in fileRe.allMatches(content)) {
      final pth = m.group(1)?.trim();
      if (pth != null &&
          pth.isNotEmpty &&
          !pth.startsWith('http') &&
          !pth.startsWith('data:')) {
        out.add(SandboxPathResolver.fix(pth));
      }
    }
    return out;
  }

  Future<void> _migrateSandboxPaths() async {
    try {
      // No-op if empty
      if (_messagesBox.isEmpty) return;
      final imgRe = RegExp(r"\[image:(.+?)\]");
      final fileRe = RegExp(r"\[file:(.+?)\|(.+?)\|(.+?)\]");

      for (final key in _messagesBox.keys) {
        final msg = _messagesBox.get(key);
        if (msg == null) continue;
        final content = msg.content;
        String updated = content;
        bool changed = false;

        // Rewrite image paths
        updated = updated.replaceAllMapped(imgRe, (m) {
          final raw = (m.group(1) ?? '').trim();
          final fixed = SandboxPathResolver.fix(raw);
          if (fixed != raw) changed = true;
          return '[image:$fixed]';
        });

        // Rewrite file attachment paths
        updated = updated.replaceAllMapped(fileRe, (m) {
          final raw = (m.group(1) ?? '').trim();
          final name = (m.group(2) ?? '').trim();
          final mime = (m.group(3) ?? '').trim();
          final fixed = SandboxPathResolver.fix(raw);
          if (fixed != raw) changed = true;
          return '[file:$fixed|$name|$mime]';
        });

        if (changed && updated != content) {
          final newMsg = msg.copyWith(content: updated);
          await _messagesBox.put(msg.id, newMsg);
        }
      }
    } catch (_) {
      // best-effort migration; ignore errors
    }
  }

  Future<void> _resetStaleStreamingFlags() async {
    try {
      final raw = _toolEventsBox.get(_activeStreamingKey);
      if (raw == null) return;
      final ids = (raw as List).cast<String>();
      if (ids.isEmpty) return;
      for (final id in ids) {
        final msg = _messagesBox.get(id);
        if (msg != null && msg.isStreaming) {
          await _messagesBox.put(id, msg.copyWith(isStreaming: false));
        }
      }
      await _toolEventsBox.delete(_activeStreamingKey);
    } catch (_) {
      // best-effort; ignore errors
    }
  }

  void _trackStreamingId(String messageId) {
    try {
      final raw = _toolEventsBox.get(_activeStreamingKey);
      final ids = raw != null
          ? (raw as List).cast<String>().toList()
          : <String>[];
      if (!ids.contains(messageId)) {
        ids.add(messageId);
        _toolEventsBox.put(_activeStreamingKey, ids);
      }
    } catch (_) {}
  }

  void _untrackStreamingId(String messageId) {
    try {
      final raw = _toolEventsBox.get(_activeStreamingKey);
      if (raw == null) return;
      final ids = (raw as List).cast<String>().toList();
      if (ids.remove(messageId)) {
        if (ids.isEmpty) {
          _toolEventsBox.delete(_activeStreamingKey);
        } else {
          _toolEventsBox.put(_activeStreamingKey, ids);
        }
      }
    } catch (_) {}
  }

  Future<void> _cleanupOrphanUploads() async {
    try {
      final uploadDir = await AppDirectories.getUploadDirectory();
      if (!await uploadDir.exists()) return;

      String canon(String pth) {
        final normalized = p.normalize(pth);
        return Platform.isWindows ? normalized.toLowerCase() : normalized;
      }

      final referenced = <String>{};
      for (final m in _messagesBox.values) {
        for (final pth in _extractAttachmentPaths(m.content)) {
          referenced.add(canon(pth));
        }
      }

      final entries = uploadDir.listSync(recursive: true, followLinks: false);
      for (final ent in entries) {
        if (ent is File) {
          final filePath = canon(ent.path);
          if (!referenced.contains(filePath)) {
            try {
              await ent.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  Future<void> restoreConversation(
    Conversation conversation,
    List<ChatMessage> messages,
  ) async {
    if (!_initialized) await init();
    for (final m in messages) {
      await _messagesBox.put(m.id, m);
    }
    final ids = messages.map((m) => m.id).toList();
    final restored = Conversation(
      id: conversation.id,
      title: conversation.title,
      createdAt: conversation.createdAt,
      updatedAt: conversation.updatedAt,
      messageIds: ids,
      isPinned: conversation.isPinned,
      mcpServerIds: List.of(conversation.mcpServerIds),
      truncateIndex: conversation.truncateIndex,
      assistantId: conversation.assistantId,
      versionSelections: Map<String, int>.from(conversation.versionSelections),
    );
    await _conversationsBox.put(restored.id, restored);
    _messagesCache[restored.id] = List.of(messages);
    notifyListeners();
  }

  Future<void> addMessageDirectly(
    String conversationId,
    ChatMessage message,
  ) async {
    if (!_initialized) await init();
    await _messagesBox.put(message.id, message);
    final conversation = _conversationsBox.get(conversationId);
    if (conversation != null) {
      if (!conversation.messageIds.contains(message.id)) {
        conversation.messageIds.add(message.id);
        await conversation.save();
      }
    }
    if (_messagesCache.containsKey(conversationId)) {
      if (!_messagesCache[conversationId]!.any((m) => m.id == message.id)) {
        _messagesCache[conversationId]!.add(message);
      }
    }
    notifyListeners();
  }

  List<String> getConversationMcpServers(String conversationId) {
    if (!_initialized) return const <String>[];
    final c =
        _conversationsBox.get(conversationId) ??
        _draftConversations[conversationId];
    return c?.mcpServerIds ?? const <String>[];
  }

  Future<void> setConversationMcpServers(
    String conversationId,
    List<String> serverIds,
  ) async {
    if (!_initialized) await init();
    if (_draftConversations.containsKey(conversationId)) {
      final draft = _draftConversations[conversationId]!;
      draft.mcpServerIds = List.of(serverIds);
      draft.updatedAt = DateTime.now();
      notifyListeners();
      return;
    }
    final c = _conversationsBox.get(conversationId);
    if (c == null) return;
    c.mcpServerIds = List.of(serverIds);
    c.updatedAt = DateTime.now();
    await c.save();
    notifyListeners();
  }

  Future<void> toggleConversationMcpServer(
    String conversationId,
    String serverId,
    bool enabled,
  ) async {
    final current = getConversationMcpServers(conversationId);
    final set = current.toSet();
    if (enabled) {
      set.add(serverId);
    } else {
      set.remove(serverId);
    }
    await setConversationMcpServers(conversationId, set.toList());
  }

  Future<void> renameConversation(String id, String newTitle) async {
    if (!_initialized) return;
    if (_draftConversations.containsKey(id)) {
      final draft = _draftConversations[id]!;
      draft.title = newTitle;
      draft.updatedAt = DateTime.now();
      notifyListeners();
      return;
    }
    final conversation = _conversationsBox.get(id);
    if (conversation == null) return;
    conversation.title = newTitle;
    conversation.updatedAt = DateTime.now();
    await conversation.save();
    notifyListeners();
  }

  Future<void> updateConversationSummary(
    String id,
    String summary,
    int messageCount,
  ) async {
    if (!_initialized) return;
    if (_draftConversations.containsKey(id)) {
      final draft = _draftConversations[id]!;
      draft.summary = summary;
      draft.lastSummarizedMessageCount = messageCount;
      notifyListeners();
      return;
    }
    final conversation = _conversationsBox.get(id);
    if (conversation == null) return;
    conversation.summary = summary;
    conversation.lastSummarizedMessageCount = messageCount;
    await conversation.save();
    notifyListeners();
  }

  List<Conversation> getConversationsWithSummaryForAssistant(
    String assistantId,
  ) {
    if (!_initialized) return [];
    return getAllConversations()
        .where(
          (c) =>
              c.assistantId == assistantId &&
              c.summary != null &&
              c.summary!.trim().isNotEmpty,
        )
        .toList();
  }

  Future<void> clearConversationSummary(String conversationId) async {
    if (!_initialized) return;
    if (_draftConversations.containsKey(conversationId)) {
      final draft = _draftConversations[conversationId]!;
      draft.summary = null;
      draft.lastSummarizedMessageCount = 0;
      notifyListeners();
      return;
    }
    final conversation = _conversationsBox.get(conversationId);
    if (conversation == null) return;
    conversation.summary = null;
    conversation.lastSummarizedMessageCount = 0;
    await conversation.save();
    notifyListeners();
  }

  Future<void> togglePinConversation(String id) async {
    if (!_initialized) return;
    if (_draftConversations.containsKey(id)) {
      final draft = _draftConversations[id]!;
      draft.isPinned = !draft.isPinned;
      notifyListeners();
      return;
    }
    final conversation = _conversationsBox.get(id);
    if (conversation == null) return;
    conversation.isPinned = !conversation.isPinned;
    await conversation.save();
    notifyListeners();
  }

  Future<ChatMessage> addMessage({
    required String conversationId,
    required String role,
    required String content,
    String? modelId,
    String? providerId,
    int? totalTokens,
    bool isStreaming = false,
    String? reasoningText,
    DateTime? reasoningStartAt,
    DateTime? reasoningFinishedAt,
    String? groupId,
    int? version,
  }) async {
    if (!_initialized) await init();

    var conversation = _conversationsBox.get(conversationId);
    if (conversation == null) {
      final draft = _draftConversations.remove(conversationId);
      if (draft != null) {
        await _conversationsBox.put(draft.id, draft);
        conversation = draft;
      } else {
        conversation = Conversation(
          id: conversationId,
          title: _defaultConversationTitle,
        );
        await _conversationsBox.put(conversationId, conversation);
      }
    }

    final message = ChatMessage(
      role: role,
      content: content,
      conversationId: conversationId,
      modelId: modelId,
      providerId: providerId,
      totalTokens: totalTokens,
      isStreaming: isStreaming,
      reasoningText: reasoningText,
      reasoningStartAt: reasoningStartAt,
      reasoningFinishedAt: reasoningFinishedAt,
      groupId: groupId,
      version: version,
    );

    await _messagesBox.put(message.id, message);

    if (isStreaming) {
      _trackStreamingId(message.id);
    }

    conversation.messageIds.add(message.id);
    conversation.updatedAt = DateTime.now();
    await conversation.save();

    if (_messagesCache.containsKey(conversationId)) {
      _messagesCache[conversationId]!.add(message);
    }

    notifyListeners();
    return message;
  }

  Future<void> updateMessage(
    String messageId, {
    String? content,
    int? totalTokens,
    bool? isStreaming,
    String? reasoningText,
    DateTime? reasoningStartAt,
    DateTime? reasoningFinishedAt,
    String? translation,
    String? reasoningSegmentsJson,
    int? promptTokens,
    int? completionTokens,
    int? cachedTokens,
    int? durationMs,
  }) async {
    if (!_initialized) return;
    final message = _messagesBox.get(messageId);
    if (message == null) return;
    final updatedMessage = message.copyWith(
      content: content ?? message.content,
      totalTokens: totalTokens ?? message.totalTokens,
      isStreaming: isStreaming ?? message.isStreaming,
      reasoningText: reasoningText ?? message.reasoningText,
      reasoningStartAt: reasoningStartAt ?? message.reasoningStartAt,
      reasoningFinishedAt: reasoningFinishedAt ?? message.reasoningFinishedAt,
      translation: translation,
      reasoningSegmentsJson:
          reasoningSegmentsJson ?? message.reasoningSegmentsJson,
      promptTokens: promptTokens ?? message.promptTokens,
      completionTokens: completionTokens ?? message.completionTokens,
      cachedTokens: cachedTokens ?? message.cachedTokens,
      durationMs: durationMs ?? message.durationMs,
    );
    await _messagesBox.put(messageId, updatedMessage);
    if (isStreaming == false) {
      _untrackStreamingId(messageId);
    }
    final conversationId = message.conversationId;
    if (_messagesCache.containsKey(conversationId)) {
      final messages = _messagesCache[conversationId]!;
      final index = messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        messages[index] = updatedMessage;
      }
    }
    notifyListeners();
  }

  Future<void> updateMessageSilent(
    String messageId, {
    String? content,
    int? totalTokens,
    bool? isStreaming,
    String? reasoningText,
    DateTime? reasoningStartAt,
    DateTime? reasoningFinishedAt,
    String? translation,
    String? reasoningSegmentsJson,
    int? promptTokens,
    int? completionTokens,
    int? cachedTokens,
    int? durationMs,
  }) async {
    if (!_initialized) return;
    final message = _messagesBox.get(messageId);
    if (message == null) return;
    final updatedMessage = message.copyWith(
      content: content ?? message.content,
      totalTokens: totalTokens ?? message.totalTokens,
      isStreaming: isStreaming ?? message.isStreaming,
      reasoningText: reasoningText ?? message.reasoningText,
      reasoningStartAt: reasoningStartAt ?? message.reasoningStartAt,
      reasoningFinishedAt: reasoningFinishedAt ?? message.reasoningFinishedAt,
      translation: translation,
      reasoningSegmentsJson:
          reasoningSegmentsJson ?? message.reasoningSegmentsJson,
      promptTokens: promptTokens ?? message.promptTokens,
      completionTokens: completionTokens ?? message.completionTokens,
      cachedTokens: cachedTokens ?? message.cachedTokens,
      durationMs: durationMs ?? message.durationMs,
    );
    await _messagesBox.put(messageId, updatedMessage);
    if (isStreaming == false) {
      _untrackStreamingId(messageId);
    }
    final conversationId = message.conversationId;
    if (_messagesCache.containsKey(conversationId)) {
      final messages = _messagesCache[conversationId]!;
      final index = messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        messages[index] = updatedMessage;
      }
    }
  }

  List<Map<String, dynamic>> getToolEvents(String assistantMessageId) {
    if (!_initialized) return const <Map<String, dynamic>>[];
    final v = _toolEventsBox.get(assistantMessageId);
    if (v is List) {
      return v
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<void> setToolEvents(
    String assistantMessageId,
    List<Map<String, dynamic>> events,
  ) async {
    if (!_initialized) await init();
    await _toolEventsBox.put(assistantMessageId, events);
    notifyListeners();
  }

  Future<void> upsertToolEvent(
    String assistantMessageId, {
    required String id,
    required String name,
    required Map<String, dynamic> arguments,
    String? content,
  }) async {
    if (!_initialized) await init();
    final list = List<Map<String, dynamic>>.of(
      getToolEvents(assistantMessageId),
    );
    final cleanId = (id).toString();
    int idx = -1;
    if (cleanId.isNotEmpty) {
      idx = list.indexWhere((e) => (e['id']?.toString() ?? '') == cleanId);
    }
    if (idx < 0) {
      idx = list.indexWhere(
        (e) =>
            (e['name']?.toString() ?? '') == name &&
            (e['content'] == null ||
                (e['content']?.toString().isEmpty ?? true)),
      );
    }
    final record = <String, dynamic>{
      'id': cleanId,
      'name': name,
      'arguments': arguments,
      'content': content,
    };
    if (idx >= 0) {
      list[idx] = record;
    } else {
      list.add(record);
    }
    await _toolEventsBox.put(assistantMessageId, list);
    notifyListeners();
  }

  String? getGeminiThoughtSignature(String assistantMessageId) {
    if (!_initialized) return null;
    final v = _toolEventsBox.get(_sigKey(assistantMessageId));
    if (v is String && v.trim().isNotEmpty) return v;
    return null;
  }

  Future<void> setGeminiThoughtSignature(
    String assistantMessageId,
    String signature,
  ) async {
    if (!_initialized) await init();
    await _toolEventsBox.put(_sigKey(assistantMessageId), signature);
    notifyListeners();
  }

  Future<void> removeGeminiThoughtSignature(String assistantMessageId) async {
    if (!_initialized) await init();
    try {
      await _toolEventsBox.delete(_sigKey(assistantMessageId));
    } catch (_) {}
  }

  Future<Conversation> forkConversation({
    required String title,
    required String? assistantId,
    required List<ChatMessage> sourceMessages,
    Map<String, int>? versionSelections,
  }) async {
    if (!_initialized) await init();
    final convo = await createConversation(
      title: title,
      assistantId: assistantId,
    );
    final ids = <String>[];
    for (final src in sourceMessages) {
      final clone = ChatMessage(
        role: src.role,
        content: src.content,
        timestamp: src.timestamp,
        modelId: src.modelId,
        providerId: src.providerId,
        totalTokens: src.totalTokens,
        conversationId: convo.id,
        isStreaming: false,
        reasoningText: src.reasoningText,
        reasoningStartAt: src.reasoningStartAt,
        reasoningFinishedAt: src.reasoningFinishedAt,
        translation: src.translation,
        reasoningSegmentsJson: src.reasoningSegmentsJson,
        groupId: src.groupId,
        version: src.version,
      );
      await _messagesBox.put(clone.id, clone);
      ids.add(clone.id);
    }
    final c = _conversationsBox.get(convo.id);
    if (c != null) {
      c.messageIds
        ..clear()
        ..addAll(ids);
      c.versionSelections = Map<String, int>.from(
        versionSelections ?? const <String, int>{},
      );
      c.updatedAt = DateTime.now();
      await c.save();
    }
    _messagesCache[convo.id] = [for (final id in ids) _messagesBox.get(id)!];
    notifyListeners();
    return _conversationsBox.get(convo.id)!;
  }

  Future<ChatMessage?> appendMessageVersion({
    required String messageId,
    required String content,
  }) async {
    if (!_initialized) await init();
    final original = _messagesBox.get(messageId);
    if (original == null) return null;
    final cid = original.conversationId;
    final convo = _conversationsBox.get(cid) ?? _draftConversations[cid];
    if (convo == null) return null;
    final gid = (original.groupId ?? original.id);
    int maxVersion = -1;
    for (final mid in convo.messageIds) {
      final m = _messagesBox.get(mid);
      if (m == null) continue;
      final mg = (m.groupId ?? m.id);
      if (mg == gid) {
        if (m.version > maxVersion) maxVersion = m.version;
      }
    }
    final nextVersion = maxVersion + 1;
    final newMsg = ChatMessage(
      role: original.role,
      content: content,
      conversationId: cid,
      modelId: original.modelId,
      providerId: original.providerId,
      totalTokens: null,
      isStreaming: false,
      groupId: gid,
      version: nextVersion,
    );
    await _messagesBox.put(newMsg.id, newMsg);
    if (_draftConversations.containsKey(cid)) {
      final draft = _draftConversations[cid]!;
      draft.messageIds.add(newMsg.id);
      draft.updatedAt = DateTime.now();
      draft.versionSelections[gid] = nextVersion;
    } else {
      final c = _conversationsBox.get(cid);
      if (c != null) {
        c.messageIds.add(newMsg.id);
        c.updatedAt = DateTime.now();
        c.versionSelections[gid] = nextVersion;
        await c.save();
      }
    }
    final arr = _messagesCache[cid];
    if (arr != null) arr.add(newMsg);
    notifyListeners();
    return newMsg;
  }

  Map<String, int> getVersionSelections(String conversationId) {
    final c =
        _conversationsBox.get(conversationId) ??
        _draftConversations[conversationId];
    return Map<String, int>.from(c?.versionSelections ?? const <String, int>{});
  }

  Future<void> setSelectedVersion(
    String conversationId,
    String groupId,
    int version,
  ) async {
    if (_draftConversations.containsKey(conversationId)) {
      final draft = _draftConversations[conversationId]!;
      draft.versionSelections[groupId] = version;
      draft.updatedAt = DateTime.now();
      notifyListeners();
      return;
    }
    final c = _conversationsBox.get(conversationId);
    if (c == null) return;
    c.versionSelections[groupId] = version;
    c.updatedAt = DateTime.now();
    await c.save();
    notifyListeners();
  }

  Future<void> clearSelectedVersion(
    String conversationId,
    String groupId,
  ) async {
    if (_draftConversations.containsKey(conversationId)) {
      final draft = _draftConversations[conversationId]!;
      draft.versionSelections.remove(groupId);
      draft.updatedAt = DateTime.now();
      notifyListeners();
      return;
    }
    final c = _conversationsBox.get(conversationId);
    if (c == null) return;
    c.versionSelections.remove(groupId);
    c.updatedAt = DateTime.now();
    await c.save();
    notifyListeners();
  }

  Future<Conversation?> toggleTruncateAtTail(
    String conversationId, {
    String? defaultTitle,
  }) async {
    if (!_initialized) await init();
    if (_draftConversations.containsKey(conversationId)) {
      final draft = _draftConversations[conversationId]!;
      final lastIndexPlusOne = draft.messageIds.length;
      final newValue = (draft.truncateIndex == lastIndexPlusOne)
          ? -1
          : lastIndexPlusOne;
      draft.truncateIndex = newValue;
      if ((defaultTitle ?? '').isNotEmpty) draft.title = defaultTitle!;
      draft.updatedAt = DateTime.now();
      notifyListeners();
      return draft;
    }
    final c = _conversationsBox.get(conversationId);
    if (c == null) return null;
    final lastIndexPlusOne = c.messageIds.length;
    final newValue = (c.truncateIndex == lastIndexPlusOne)
        ? -1
        : lastIndexPlusOne;
    c.truncateIndex = newValue;
    if ((defaultTitle ?? '').isNotEmpty) c.title = defaultTitle!;
    c.updatedAt = DateTime.now();
    await c.save();
    notifyListeners();
    return c;
  }

  Future<void> deleteMessage(String messageId) async {
    if (!_initialized) return;
    final message = _messagesBox.get(messageId);
    if (message == null) return;
    final conversation = _conversationsBox.get(message.conversationId);
    if (conversation != null) {
      final gid = message.groupId ?? message.id;
      final ids = conversation.messageIds;
      int anchorIndex = -1;
      for (int i = 0; i < ids.length; i++) {
        final mid = ids[i];
        final m = _messagesBox.get(mid);
        if (m == null) continue;
        final mgid = m.groupId ?? m.id;
        if (mgid == gid) {
          anchorIndex = i;
          break;
        }
      }
      ids.remove(messageId);
      if (anchorIndex >= 0) {
        int? earliestRemaining;
        for (int i = 0; i < ids.length; i++) {
          final mid = ids[i];
          final m = _messagesBox.get(mid);
          if (m == null) continue;
          final mgid = m.groupId ?? m.id;
          if (mgid == gid) {
            earliestRemaining = i;
            break;
          }
        }
        if (earliestRemaining != null && earliestRemaining > anchorIndex) {
          final replacementId = ids.removeAt(earliestRemaining);
          final insertAt = anchorIndex <= ids.length ? anchorIndex : ids.length;
          ids.insert(insertAt, replacementId);
        }
      }
      await conversation.save();
    }
    await _messagesBox.delete(messageId);
    if (message.role == 'assistant') {
      try {
        await _toolEventsBox.delete(message.id);
      } catch (_) {}
      try {
        await _toolEventsBox.delete(_sigKey(message.id));
      } catch (_) {}
    }
    _messagesCache.remove(message.conversationId);
    await _cleanupOrphanUploads();
    notifyListeners();
  }

  void setCurrentConversation(String? id) {
    _currentConversationId = id;
    notifyListeners();
  }

  Future<void> clearAllData() async {
    if (!_initialized) return;
    await _messagesBox.clear();
    await _conversationsBox.clear();
    await _toolEventsBox.clear();
    _messagesCache.clear();
    _draftConversations.clear();
    _currentConversationId = null;
    try {
      final uploadDir = await AppDirectories.getUploadDirectory();
      if (await uploadDir.exists()) {
        await uploadDir.delete(recursive: true);
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<UploadStats> getUploadStats() async {
    try {
      final uploadDir = await AppDirectories.getUploadDirectory();
      if (!await uploadDir.exists()) {
        return const UploadStats(fileCount: 0, totalBytes: 0);
      }
      int count = 0;
      int bytes = 0;
      final entries = uploadDir.listSync(recursive: true, followLinks: false);
      for (final ent in entries) {
        if (ent is File) {
          count += 1;
          try {
            bytes += await ent.length();
          } catch (_) {}
        }
      }
      return UploadStats(fileCount: count, totalBytes: bytes);
    } catch (_) {
      return const UploadStats(fileCount: 0, totalBytes: 0);
    }
  }

  Future<void> moveConversationToAssistant({
    required String conversationId,
    required String assistantId,
  }) async {
    if (!_initialized) await init();
    if (_draftConversations.containsKey(conversationId)) {
      final draft = _draftConversations[conversationId]!;
      draft.assistantId = assistantId;
      draft.updatedAt = DateTime.now();
      notifyListeners();
      return;
    }
    final c = _conversationsBox.get(conversationId);
    if (c == null) return;
    c.assistantId = assistantId;
    c.updatedAt = DateTime.now();
    await c.save();
    notifyListeners();
  }
}

class UploadStats {
  final int fileCount;
  final int totalBytes;
  const UploadStats({required this.fileCount, required this.totalBytes});
}