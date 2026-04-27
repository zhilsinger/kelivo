import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/unified_thread.dart';
import '../services/supabase_thread_sync_service.dart';

/// Manages the lifecycle of imported chat threads entirely in memory.
/// 1. Raw import (JSON/File) -> parse -> dedup -> pending review
/// 2. User confirms -> save to in-memory map -> sync to Supabase
/// 3. User can view, export, or delete backed-up threads
///
/// NOTE: Threads are NOT persisted to Hive to avoid requiring build_runner
/// for Hive adapter generation. Call exportAll() to serialize for file storage.
class ThreadBackupProvider extends ChangeNotifier {
  final SupabaseThreadSyncService _syncService;

  /// Backed-up threads stored in memory, keyed by thread id
  final Map<String, UnifiedThread> _threads = {};

  /// Pending imports waiting for user confirmation
  List<UnifiedThread> _pendingImports = [];
  List<UnifiedThread> get pendingImports => List.unmodifiable(_pendingImports);

  /// All backed-up threads
  List<UnifiedThread> get backedUpThreads => _threads.values.toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  ThreadBackupProvider({
    required SupabaseThreadSyncService syncService,
  }) : _syncService = syncService;

  /// Import threads from parsed data (JSON). Deduplicates by id.
  void importFromParsed(List<UnifiedThread> threads) {
    final existingIds = _pendingImports.map((t) => t.id).toSet();
    existingIds.addAll(_threads.keys);

    final newThreads = <UnifiedThread>[];
    for (final thread in threads) {
      if (!existingIds.contains(thread.id)) {
        newThreads.add(thread);
        existingIds.add(thread.id);
      }
    }

    _pendingImports.addAll(newThreads);
    notifyListeners();
  }

  /// Confirm import: save to map and sync to Supabase
  Future<void> confirmImport() async {
    if (_pendingImports.isEmpty) return;

    final toImport = List<UnifiedThread>.from(_pendingImports);
    _pendingImports.clear();
    notifyListeners();

    // Save to in-memory map
    for (final thread in toImport) {
      _threads[thread.id] = thread;
    }

    // Sync to Supabase (fire-and-forget, no blocking)
    if (_syncService.isConfigured) {
      for (final thread in toImport) {
        _syncService.pushThread(thread).then((result) {
          if (result.success) {
            final updated = thread.copyWith(syncedToCloud: true);
            _threads[thread.id] = updated;
          }
          debugPrint(
            '[SupabaseSync] Thread ${thread.id}: ${result.success ? "synced" : "failed - ${result.error}"}',
          );
        });
      }
    }
  }

  /// Clear pending imports without saving
  void clearPending() {
    _pendingImports.clear();
    notifyListeners();
  }

  /// Delete a backed-up thread locally and optionally from Supabase
  Future<void> deleteThread(String threadId, {bool deleteFromCloud = true}) async {
    _threads.remove(threadId);
    if (deleteFromCloud && _syncService.isConfigured) {
      _syncService.deleteThread(threadId);
    }
    notifyListeners();
  }

  /// Delete all backed-up threads
  Future<void> deleteAllThreads({bool deleteFromCloud = true}) async {
    final ids = _threads.keys.toList();
    _threads.clear();
    if (deleteFromCloud && _syncService.isConfigured) {
      for (final id in ids) {
        _syncService.deleteThread(id);
      }
    }
    notifyListeners();
  }

  /// Get count of backed-up threads
  int get threadCount => _threads.length;

  /// Check if there are pending imports
  bool get hasPendingImports => _pendingImports.isNotEmpty;

  /// Export all threads as a JSON-serializable list
  List<Map<String, dynamic>> exportAll() =>
      _threads.values.map((t) => t.toJson()).toList();

  /// Load threads from a list of JSON maps (e.g. restored from file)
  void loadFromJsonList(List<Map<String, dynamic>> jsonList) {
    for (final json in jsonList) {
      try {
        final thread = UnifiedThread.fromJson(json);
        _threads[thread.id] = thread;
      } catch (e) {
        debugPrint('[ThreadBackupProvider] Failed to load thread: $e');
      }
    }
    notifyListeners();
  }
}