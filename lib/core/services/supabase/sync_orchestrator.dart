import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:battery_plus/battery_plus.dart';

import 'sync_queue.dart';
import 'supabase_client_service.dart';
import 'supabase_index_service.dart';
import 'supabase_message_serializer.dart';
import 'supabase_conflict_resolver.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';

/// Status of the sync subsystem (used for UI binding).
enum SyncStatus { idle, syncing, paused, error }

/// Orchestrates the full sync pipeline: queue, process, backpressure.
class SyncOrchestrator extends ChangeNotifier {
  SyncOrchestrator._();
  static final SyncOrchestrator instance = SyncOrchestrator._();

  static const String _queueBoxName = 'supabase_sync_queue_v1';
  static const int _maxRetries = 5;
  static const int _batchSize = 20;
  static const int _minBatteryPercent = 15;
  static const String _conversationsBoxName = 'conversations';
  static const String _messagesBoxName = 'messages';

  late Box<SyncJob> _queueBox;

  bool _initialized = false;
  bool _isProcessing = false;
  bool _paused = false;
  SyncStatus _status = SyncStatus.idle;
  Timer? _periodicTimer;
  bool _wifiOnly = false;
  String? _userId;

  final SupabaseConflictResolver _conflictResolver = const SupabaseConflictResolver();

  // Chunk indexing
  SupabaseIndexService? _indexService;
  bool _indexEnabled = true;

  bool get initialized => _initialized;
  bool get isProcessing => _isProcessing;
  bool get isPaused => _paused;
  SyncStatus get status => _status;

  int get pendingCount => _initialized ? _queueBox.length : 0;

  int get deadLetterCount =>
      _initialized
      ? _queueBox.values.where((j) => j.retryCount >= _maxRetries).length
      : 0;

  Future<void> init({
    required String userId,
    bool wifiOnly = false,
  }) async {
    if (_initialized) return;
    if (!Hive.isAdapterRegistered(100)) {
      Hive.registerAdapter(SyncJobAdapter());
    }
    _queueBox = await Hive.openBox<SyncJob>(_queueBoxName);
    _userId = userId;
    _wifiOnly = wifiOnly;
    _initialized = true;
  }

  void configure({String? userId, bool? wifiOnly}) {
    if (userId != null) _userId = userId;
    if (wifiOnly != null) _wifiOnly = wifiOnly;
  }

  void configureIndexing({
    SupabaseIndexService? indexService,
    bool? indexEnabled,
  }) {
    if (indexService != null) _indexService = indexService;
    if (indexEnabled != null) _indexEnabled = indexEnabled;
  }

  void clear() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _isProcessing = false;
    _paused = false;
    _status = SyncStatus.idle;
    _initialized = false;
    _userId = null;
    _indexService = null;
  }

  void enqueueThread(String conversationId) {
    if (!_initialized || _userId == null) return;
    if (!SupabaseClientService.instance.isConfigured) return;
    _dedupeAndEnqueue(
      entityType: 'thread', entityId: conversationId, operation: 'upsert',
    );
  }

  void enqueueThreadDeletion(String conversationId) {
    if (!_initialized || _userId == null) return;
    if (!SupabaseClientService.instance.isConfigured) return;
    _dedupeAndEnqueue(
      entityType: 'thread', entityId: conversationId, operation: 'delete',
    );
  }

  void _dedupeAndEnqueue({
    required String entityType, required String entityId,
    required String operation, String? payloadJson,
  }) {
    final keysToRemove = <dynamic>[];
    for (final key in _queueBox.keys) {
      final job = _queueBox.get(key);
      if (job != null &&
          job.entityType == entityType &&
          job.entityId == entityId &&
          job.retryCount < _maxRetries) {
        keysToRemove.add(key);
      }
    }
    for (final key in keysToRemove) {
      _queueBox.delete(key);
    }
    final job = SyncJob(
      entityType: entityType, entityId: entityId,
      operation: operation, payloadJson: payloadJson,
    );
    _queueBox.put(job.id, job);
    _scheduleProcess();
  }

  Timer? _scheduleDebounce;
  void _scheduleProcess() {
    _scheduleDebounce?.cancel();
    _scheduleDebounce = Timer(const Duration(seconds: 2), () {
      processQueue();
    });
  }

  Future<void> processQueue() async {
    if (!_initialized || _isProcessing || _paused) return;
    if (!SupabaseClientService.instance.isConfigured) return;
    if (_userId == null || _userId!.isEmpty) return;

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) return;
    if (_wifiOnly && !connectivity.contains(ConnectivityResult.wifi)) return;

    try {
      final battery = Battery();
      final level = await battery.batteryLevel;
      if (level < _minBatteryPercent) return;
    } catch (_) {}

    _isProcessing = true;
    _status = SyncStatus.syncing;
    notifyListeners();

    try {
      final activeJobs = _queueBox.values
          .where((j) => j.retryCount < _maxRetries)
          .toList();
      if (activeJobs.isEmpty) {
        _status = SyncStatus.idle;
        notifyListeners();
        return;
      }

      final batch = activeJobs.take(_batchSize).toList();
      final client = SupabaseClientService.instance;
      final conversationsBox = Hive.box<Conversation>(_conversationsBoxName);
      final messagesBox = Hive.box<ChatMessage>(_messagesBoxName);

      for (final job in batch) {
        try {
          if (job.operation == 'delete') {
            if (job.entityType == 'thread') {
              await client.deleteThread(job.entityId);
            }
            await _queueBox.delete(job.id);
          } else {
            if (job.entityType == 'thread') {
              final conversation = conversationsBox.get(job.entityId);
              if (conversation == null) {
                await _queueBox.delete(job.id);
                continue;
              }

              // Build message payloads using sidecar serializer (Phase 7)
              final messagePayloads = <Map<String, dynamic>>[];
              for (final msgId in conversation.messageIds) {
                final msg = messagesBox.get(msgId);
                if (msg != null) {
                  messagePayloads.add(SupabaseMessageSerializer.serializeMessage(
                    msg, userId: _userId!, threadId: conversation.id,
                  ));
                }
              }

              await client.upsertThread(
                SupabaseMessageSerializer.serializeConversation(
                  conversation, userId: _userId!,
                ),
              );

              if (messagePayloads.isNotEmpty) {
                final withUserId = messagePayloads.map((m) => {
                  ...m,
                  'user_id': _userId,
                }).toList();
                await client.upsertMessages(withUserId);
              }

              // Update sync manifest after successful sync
              try {
                await client.upsertSyncManifest({
                  'user_id': _userId,
                  'entity_type': 'thread',
                  'entity_id': conversation.id,
                  'content_hash': conversation.updatedAt
                      .millisecondsSinceEpoch.toString(),
                  'sync_status': 'synced',
                });
              } catch (_) {}

              // Conflict detection (Phase 7)
              try {
                final remoteManifest = await client.getSyncManifest('thread', conversation.id);
                if (remoteManifest != null) {
                  final localState = ThreadSyncState.fromConversation(conversation);
                  final remoteState = ThreadSyncState.fromRemoteMap(remoteManifest);
                  final result = _conflictResolver.resolve(local: localState, remote: remoteState);
                  if (result.outcome == ConflictOutcome.manualReview && result.conflict != null) {
                    await client.upsertSyncConflict(result.conflict!.toJson());
                  }
                }
              } catch (_) {}

              await _queueBox.delete(job.id);

              // Chunk indexing
              try {
                if (_indexService != null && _indexEnabled) {
                  await _indexService!.indexThread(
                    threadId: conversation.id,
                    threadTitle: conversation.title,
                    messages: messagePayloads,
                  );
                }
              } catch (_) {}
            }
          }
        } catch (e) {
          final nextRetry = job.retryCount + 1;
          final errorStr = e.toString();
          if (nextRetry >= _maxRetries) {
            final updated = job.copyWith(retryCount: nextRetry, lastError: errorStr);
            await _queueBox.put(job.id, updated);
          } else {
            final updated = job.copyWith(retryCount: nextRetry, lastError: errorStr);
            await _queueBox.put(job.id, updated);
          }
        }
      }
    } catch (e) {
      _status = SyncStatus.error;
    } finally {
      _isProcessing = false;
      if (_status != SyncStatus.error) {
        _status = SyncStatus.idle;
      }
      notifyListeners();
    }
  }

  void pause() {
    _paused = true;
    _status = SyncStatus.paused;
    notifyListeners();
  }

  void resume() {
    _paused = false;
    _status = SyncStatus.idle;
    notifyListeners();
    processQueue();
  }

  /// Reset dead-letter jobs to retryCount=0 and re-process.
  Future<int> retryDeadLetter() async {
    if (!_initialized) return 0;
    final deadJobs = _queueBox.values
        .where((j) => j.retryCount >= _maxRetries)
        .toList();
    for (final job in deadJobs) {
      final reset = job.copyWith(retryCount: 0, lastError: null);
      await _queueBox.put(job.id, reset);
    }
    if (deadJobs.isNotEmpty) {
      notifyListeners();
      processQueue();
    }
    return deadJobs.length;
  }

  Future<int> clearFailedJobs() async {
    if (!_initialized) return 0;
    final failedKeys = <dynamic>[];
    for (final key in _queueBox.keys) {
      final job = _queueBox.get(key);
      if (job != null && job.retryCount >= _maxRetries) {
        failedKeys.add(key);
      }
    }
    for (final key in failedKeys) {
      await _queueBox.delete(key);
    }
    final count = failedKeys.length;
    if (count > 0) notifyListeners();
    return count;
  }

  Future<void> clearAll() async {
    if (!_initialized) return;
    await _queueBox.clear();
    _status = SyncStatus.idle;
    notifyListeners();
  }
}
