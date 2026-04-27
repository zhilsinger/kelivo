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
    // Agent work model adapters
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
