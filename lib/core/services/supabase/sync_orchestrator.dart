import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:battery_plus/battery_plus.dart';

import 'sync_queue.dart';
import 'supabase_client_service.dart';
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

  bool get initialized => _initialized;
  bool get isProcessing => _isProcessing;
  bool get isPaused => _paused;
  SyncStatus get status => _status;

  /// Number of pending jobs in the queue.
  int get pendingCount => _initialized ? _queueBox.length : 0;

  /// Number of failed jobs (retryCount >= maxRetries).
  int get deadLetterCount =>
      _initialized
      ? _queueBox.values.where((j) => j.retryCount >= _maxRetries).length
      : 0;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

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

  /// Update settings without re-init.
  void configure({String? userId, bool? wifiOnly}) {
    if (userId != null) _userId = userId;
    if (wifiOnly != null) _wifiOnly = wifiOnly;
  }

  void clear() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _isProcessing = false;
    _paused = false;
    _status = SyncStatus.idle;
    _initialized = false;
    _userId = null;
  }

  // ---------------------------------------------------------------------------
  // Enqueue
  // ---------------------------------------------------------------------------

  /// Fire-and-forget: enqueue a thread upsert. Called from ChatService hooks.
  void enqueueThread(String conversationId) {
    if (!_initialized || _userId == null) return;
    if (!SupabaseClientService.instance.isConfigured) return;

    _dedupeAndEnqueue(
      entityType: 'thread',
      entityId: conversationId,
      operation: 'upsert',
    );
  }

  /// Fire-and-forget: enqueue a thread delete.
  void enqueueThreadDeletion(String conversationId) {
    if (!_initialized || _userId == null) return;
    if (!SupabaseClientService.instance.isConfigured) return;

    _dedupeAndEnqueue(
      entityType: 'thread',
      entityId: conversationId,
      operation: 'delete',
    );
  }

  /// Remove duplicate jobs for the same entity and replace with the new one.
  void _dedupeAndEnqueue({
    required String entityType,
    required String entityId,
    required String operation,
    String? payloadJson,
  }) {
    // Remove existing jobs for the same entity
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
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payloadJson: payloadJson,
    );
    _queueBox.put(job.id, job);

    // Schedule processing after a short delay (debounce)
    _scheduleProcess();
  }

  Timer? _scheduleDebounce;
  void _scheduleProcess() {
    _scheduleDebounce?.cancel();
    _scheduleDebounce = Timer(const Duration(seconds: 2), () {
      processQueue();
    });
  }

  // ---------------------------------------------------------------------------
  // Process
  // ---------------------------------------------------------------------------

  Future<void> processQueue() async {
    if (!_initialized || _isProcessing || _paused) return;
    if (!SupabaseClientService.instance.isConfigured) return;
    if (_userId == null || _userId!.isEmpty) return;

    // Network check
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) return;

    // Wi-Fi only check
    if (_wifiOnly && !connectivity.contains(ConnectivityResult.wifi)) return;

    // Battery check
    try {
      final battery = Battery();
      final level = await battery.batteryLevel;
      if (level < _minBatteryPercent) return;
    } catch (_) {
      // Battery check best-effort; proceed if unavailable
    }

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

      // Open Hive boxes for reading conversations/messages
      final conversationsBox =
          Hive.box<Conversation>(_conversationsBoxName);
      final messagesBox = Hive.box<ChatMessage>(_messagesBoxName);

      for (final job in batch) {
        try {
          if (job.operation == 'delete') {
            if (job.entityType == 'thread') {
              await client.deleteThread(job.entityId);
            }
            await _queueBox.delete(job.id);
          } else {
            // upsert
            if (job.entityType == 'thread') {
              final conversation = conversationsBox.get(job.entityId);
              if (conversation == null) {
                // Thread no longer exists locally; remove job
                await _queueBox.delete(job.id);
                continue;
              }

              // Build message payloads
              final messagePayloads = <Map<String, dynamic>>[];
              for (final msgId in conversation.messageIds) {
                final msg = messagesBox.get(msgId);
                if (msg != null) {
                  messagePayloads.add(msg.toSupabaseJson(
                    userId: _userId!,
                    threadId: conversation.id,
                  ));
                }
              }

              await client.upsertThread(
                  conversation.toSupabaseJson(userId: _userId!));

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
                      .millisecondsSinceEpoch
                      .toString(),
                  'sync_status': 'synced',
                });
              } catch (_) {
                // Manifest update is best-effort; don't fail the job for it
              }

              await _queueBox.delete(job.id);
            }
          }
        } catch (e) {
          final nextRetry = job.retryCount + 1;
          final errorStr = e.toString();
          if (nextRetry >= _maxRetries) {
            // Dead-letter: update last error but leave in queue for inspection
            final updated = job.copyWith(
              retryCount: nextRetry,
              lastError: errorStr,
            );
            await _queueBox.put(job.id, updated);
          } else {
            final updated = job.copyWith(
              retryCount: nextRetry,
              lastError: errorStr,
            );
            await _queueBox.put(job.id, updated);
          }
        }
      }
    } catch (e) {
      _status = SyncStatus.error;
    } finally {
      _isProcessing = false;
      if (_status != SyncStatus.error) {
        final remainingActive = _queueBox.values
            .where((j) => j.retryCount < _maxRetries)
            .toList();
        _status = remainingActive.isEmpty ? SyncStatus.idle : SyncStatus.idle;
      }
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Controls
  // ---------------------------------------------------------------------------

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
