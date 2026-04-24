import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/unified_thread.dart';
import '../services/supabase_thread_sync_service.dart';

/// Manages the lifecycle of imported chat threads:
/// 1. Raw import (JSON/File) -> parse -> dedup -> pending review
/// 2. User confirms -> save to Hive -> sync to Supabase
/// 3. User can view, export, or delete backed-up threads
class ThreadBackupProvider extends ChangeNotifier {
  final Box<UnifiedThread> _box;
  final SupabaseThreadSyncService _syncService;

  /// Pending imports waiting for user confirmation
  List<UnifiedThread> _pendingImports = [];
  List<UnifiedThread> get pendingImports => List.unmodifiable(_pendingImports);

  /// All backed-up threads (persisted in Hive)
  List<UnifiedThread> get backedUpThreads => _box.values.toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  ThreadBackupProvider({
    required Box<UnifiedThread> box,
    required SupabaseThreadSyncService syncService,
  })  : _box = box,
        _syncService = syncService;

  /// Import threads from parsed data (JSON). Deduplicates by id.
  void importFromParsed(List<UnifiedThread> threads) {
    final existingIds = _pendingImports.map((t) => t.id).toSet();
    existingIds.addAll(_box.keys.cast<String>());

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

  /// Confirm import: persist to Hive and sync to Supabase
  Future<void> confirmImport() async {
    if (_pendingImports.isEmpty) return;

    final toImport = List<UnifiedThread>.from(_pendingImports);
    _pendingImports.clear();
    notifyListeners();

    // Save to Hive
    for (final thread in toImport) {
      await _box.put(thread.id, thread);
    }

    // Sync to Supabase (fire-and-forget, no blocking)
    if (_syncService.isConfigured) {
      for (final thread in toImport) {
        _syncService.pushThread(thread).then((result) {
          if (result.success) {
            final updated = thread.copyWith(syncedToCloud: true);
            _box.put(thread.id, updated);
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
    await _box.delete(threadId);
    if (deleteFromCloud && _syncService.isConfigured) {
      _syncService.deleteThread(threadId);
    }
    notifyListeners();
  }

  /// Delete all backed-up threads
  Future<void> deleteAllThreads({bool deleteFromCloud = true}) async {
    final ids = _box.keys.toList();
    await _box.clear();
    if (deleteFromCloud && _syncService.isConfigured) {
      for (final id in ids) {
        _syncService.deleteThread(id as String);
      }
    }
    notifyListeners();
  }

  /// Get count of backed-up threads
  int get threadCount => _box.length;

  /// Check if there are pending imports
  bool get hasPendingImports => _pendingImports.isNotEmpty;
}
