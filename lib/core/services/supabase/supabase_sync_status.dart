import 'package:flutter/foundation.dart';
import 'sync_orchestrator.dart';

/// Lightweight ChangeNotifier for UI binding to SyncOrchestrator state.
///
/// Registered in the Provider tree for context.watch<>() access.
/// Wraps the SyncOrchestrator singleton and exposes its state without
/// duplicating logic or requiring Provider registration of the orchestrator.
class SupabaseSyncStatus extends ChangeNotifier {
  final SyncOrchestrator _orchestrator = SyncOrchestrator.instance;

  /// Listen to orchestrator state changes.
  SupabaseSyncStatus() {
    _orchestrator.addListener(_onOrchestratorChange);
  }

  void _onOrchestratorChange() => notifyListeners();

  SyncStatus get status => _orchestrator.status;
  int get pendingCount => _orchestrator.pendingCount;
  int get deadLetterCount => _orchestrator.deadLetterCount;
  bool get isPaused => _orchestrator.isPaused;
  bool get isInitialized => _orchestrator.initialized;

  void pause() => _orchestrator.pause();
  void resume() => _orchestrator.resume();
  Future<int> retryDeadLetter() => _orchestrator.retryDeadLetter();
  Future<int> clearFailedJobs() => _orchestrator.clearFailedJobs();

  void refresh() => notifyListeners();

  @override
  void dispose() {
    _orchestrator.removeListener(_onOrchestratorChange);
    super.dispose();
  }
}
