import 'package:flutter/foundation.dart';
import '../../models/agent_timer_job.dart';
import 'agent_timer_service.dart';
import 'agent_timer_dispatcher.dart';

/// Handles recovery of timer jobs on app startup.
///
/// Loads all timers, marks overdue ones as missed, re-schedules
/// future ones, and optionally dispatches missed timers that are
/// configured for notification.
class TimerRecoveryService {
  final AgentTimerService _timerService;
  final AgentTimerDispatcher? _dispatcher;

  TimerRecoveryService({
    required AgentTimerService timerService,
    AgentTimerDispatcher? dispatcher,
  })  : _timerService = timerService,
        _dispatcher = dispatcher;

  /// Run recovery on startup.
  ///
  /// Returns the list of timers that were marked as missed.
  Future<List<AgentTimerJob>> recover() async {
    final box = await _timerService._jobs; // Access internal box for query
    final now = DateTime.now();
    final missed = <AgentTimerJob>[];

    for (final job in box.values) {
      if (job.status == TimerStatus.cancelled ||
          job.status == TimerStatus.completed ||
          job.status == TimerStatus.failed) {
        continue;
      }

      if (job.dueAt.isBefore(now)) {
        // Overdue timer — mark as missed
        if (job.status == TimerStatus.scheduled) {
          await _timerService.markMissed(job.id);
          missed.add(job);

          // Optionally dispatch missed timers
          if (_dispatcher != null && job.notifyUser) {
            try {
              await _dispatcher!.dispatch(job);
            } catch (_) {
              // Best-effort dispatch — don't fail recovery
            }
          }
        }
      } else {
        // Future timer — the AgentTimerService.scheduleTimer handles
        // the in-memory Timer creation; recovery just marks state.
      }
    }

    // Re-schedule all active timers
    await _timerService.recoverTimers();

    return missed;
  }
}
