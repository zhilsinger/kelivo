import 'package:flutter/foundation.dart';
import '../services/agent_timer/agent_timer_service.dart';
import '../models/agent_timer_job.dart';

/// Provider for agent timer state. Wraps AgentTimerService and
/// exposes active timers to the UI via ChangeNotifier.
class AgentTimerProvider extends ChangeNotifier {
  final AgentTimerService _timerService;

  AgentTimerProvider({AgentTimerService? timerService})
      : _timerService = timerService ?? AgentTimerService() {
    _timerService.addListener(_onServiceChanged);
  }

  List<AgentTimerJob> _activeTimers = [];
  List<AgentTimerJob> get activeTimers => List.unmodifiable(_activeTimers);

  /// Initialize by loading timers.
  Future<void> init() async {
    await refresh();
  }

  /// Refresh from storage.
  Future<void> refresh() async {
    _activeTimers = await _timerService.getActiveTimers();
    notifyListeners();
  }

  /// Schedule a new timer.
  Future<AgentTimerJob> scheduleTimer({
    required String title,
    required String prompt,
    required DateTime dueAt,
    String targetAssistantId = '',
    String? recurrenceRule,
    int? maxRuns,
  }) async {
    final job = await _timerService.scheduleTimer(
      title: title,
      prompt: prompt,
      targetAssistantId: targetAssistantId,
      dueAt: dueAt,
      createdByActorId: 'user',
      recurrenceRule: recurrenceRule,
      maxRuns: maxRuns,
    );
    await refresh();
    return job;
  }

  /// Cancel a timer.
  Future<void> cancelTimer(String id) async {
    await _timerService.cancelTimer(id);
    await refresh();
  }

  void _onServiceChanged() {
    refresh();
  }

  @override
  void dispose() {
    _timerService.removeListener(_onServiceChanged);
    super.dispose();
  }
}