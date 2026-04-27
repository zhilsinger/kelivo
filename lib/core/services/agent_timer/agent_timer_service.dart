import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/agent_timer_job.dart';

/// Service for managing agent timer jobs.
///
/// Must extend [ChangeNotifier] to follow the Kelivo Provider pattern.
/// Stores timer jobs in Hive and manages in-memory [Timer] instances.
/// On startup, recovers missed timers.
class AgentTimerService extends ChangeNotifier {
  static const String _boxName = 'agent_timer_jobs';

  Box<AgentTimerJob>? _box;
  final Map<String, Timer> _activeTimers = {};
  final Map<String, AgentTimerJob> _jobCache = {};

  /// Callback invoked when a timer fires.
  /// The callback receives the fired timer job.
  Future<void> Function(AgentTimerJob job)? onTimerFired;

  Future<Box<AgentTimerJob>> get _jobs async {
    if (_box == null || !_box!.isOpen) {
      _box = await Hive.openBox<AgentTimerJob>(_boxName);
    }
    return _box!;
  }

  /// Schedule a new timer job.
  Future<AgentTimerJob> scheduleTimer({
    required String title,
    required String prompt,
    required String targetAssistantId,
    required DateTime dueAt,
    required String createdByActorId,
    String createdByActorType = 'assistant',
    String? targetTeamId,
    String? targetConversationId,
    String? targetChecklistId,
    String? targetChecklistItemId,
    bool userVisible = true,
    bool notifyUser = true,
    String? recurrenceRule,
    int? maxRuns,
    List<String>? mcpServerIds,
  }) async {
    final job = AgentTimerJob(
      title: title,
      prompt: prompt,
      targetAssistantId: targetAssistantId,
      dueAt: dueAt,
      createdByActorId: createdByActorId,
      createdByActorType: createdByActorType,
      targetTeamId: targetTeamId,
      targetConversationId: targetConversationId,
      targetChecklistId: targetChecklistId,
      targetChecklistItemId: targetChecklistItemId,
      userVisible: userVisible,
      notifyUser: notifyUser,
      recurrenceRule: recurrenceRule,
      maxRuns: maxRuns,
      mcpServerIds: mcpServerIds,
    );

    final box = await _jobs;
    await box.put(job.id, job);
    _jobCache[job.id] = job;

    _scheduleTimer(job);
    notifyListeners();
    return job;
  }

  /// Cancel a timer.
  Future<void> cancelTimer(String id) async {
    final box = await _jobs;
    final job = box.get(id);
    if (job == null) return;

    final updated = job.copyWith(
      status: TimerStatus.cancelled,
      completedAt: DateTime.now(),
    );
    await box.put(id, updated);
    _jobCache[id] = updated;
    _cancelActiveTimer(id);
    notifyListeners();
  }

  /// Get all active (scheduled or firing) timers.
  Future<List<AgentTimerJob>> getActiveTimers() async {
    final box = await _jobs;
    final now = DateTime.now();
    return box.values
        .where((j) =>
            j.status == TimerStatus.scheduled ||
            j.status == TimerStatus.firing)
        .where((j) => j.dueAt.isAfter(now.subtract(const Duration(minutes: 5))))
        .toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  }

  /// Get missed timers (past due, not yet fired).
  Future<List<AgentTimerJob>> getMissedTimers() async {
    final box = await _jobs;
    final now = DateTime.now();
    return box.values
        .where((j) =>
            j.status == TimerStatus.scheduled &&
            j.dueAt.isBefore(now))
        .toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  }

  /// Get all timers (all statuses).
  Future<List<AgentTimerJob>> getAllTimers() async {
    final box = await _jobs;
    return box.values.toList()
      ..sort((a, b) => b.dueAt.compareTo(a.dueAt));
  }

  /// Mark a timer as missed after recovery.
  Future<void> markMissed(String id) async {
    final box = await _jobs;
    final job = box.get(id);
    if (job == null) return;
    final updated = job.copyWith(status: TimerStatus.missed);
    await box.put(id, updated);
    _jobCache[id] = updated;
    notifyListeners();
  }

  /// Recover active timers on startup — checks for overdue and future timers.
  Future<void> recoverTimers() async {
    final box = await _jobs;
    final now = DateTime.now();

    for (final job in box.values) {
      if (job.status == TimerStatus.cancelled ||
          job.status == TimerStatus.completed ||
          job.status == TimerStatus.failed) {
        continue;
      }

      if (job.dueAt.isBefore(now)) {
        // Overdue timer
        if (job.status == TimerStatus.scheduled) {
          // Mark as missed — user was not in app
          await markMissed(job.id);
        }
      } else {
        // Future timer — re-schedule
        _scheduleTimer(job);
      }
    }
  }

  /// Dispose all active timers (call on app shutdown).
  void disposeAll() {
    for (final timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
  }

  @override
  void dispose() {
    disposeAll();
    super.dispose();
  }

  // ─── Private ──────────────────────────────────────────────────────

  void _scheduleTimer(AgentTimerJob job) {
    _cancelActiveTimer(job.id);

    final now = DateTime.now();
    final delay = job.dueAt.difference(now);
    if (delay.isNegative) return; // already past due

    final timer = Timer(delay, () => _fireTimer(job.id));
    _activeTimers[job.id] = timer;
  }

  void _cancelActiveTimer(String id) {
    _activeTimers[id]?.cancel();
    _activeTimers.remove(id);
  }

  Future<void> _fireTimer(String id) async {
    final box = await _jobs;
    final job = box.get(id);
    if (job == null) return;
    if (job.status == TimerStatus.cancelled) return;

    _activeTimers.remove(id);

    // Update status to firing/fired
    var updated = job.copyWith(
      status: TimerStatus.fired,
      lastFiredAt: DateTime.now(),
      runCount: (job.runCount) + 1,
    );

    // Handle recurrence
    if (job.recurrenceRule != null &&
        (job.maxRuns == null || updated.runCount < job.maxRuns!)) {
      final nextDue = _computeNextDue(job);
      if (nextDue != null) {
        updated = updated.copyWith(
          status: TimerStatus.scheduled,
          dueAt: nextDue,
        );
        _scheduleTimer(updated);
      } else {
        updated = updated.copyWith(
          status: TimerStatus.completed,
          completedAt: DateTime.now(),
        );
      }
    } else {
      updated = updated.copyWith(
        status: TimerStatus.completed,
        completedAt: DateTime.now(),
      );
    }

    await box.put(id, updated);
    _jobCache[id] = updated;
    notifyListeners();

    // Notify listeners
    if (onTimerFired != null) {
      await onTimerFired!(updated);
    }
  }

  DateTime? _computeNextDue(AgentTimerJob job) {
    if (job.recurrenceRule == null) return null;
    final rule = job.recurrenceRule!.toLowerCase();

    // Simple recurrence patterns
    if (rule.startsWith('every ')) {
      final parts = rule.substring(6).trim().split(' ');
      if (parts.length >= 2) {
        final amount = int.tryParse(parts[0]) ?? 1;
        final unit = parts[1];
        switch (unit) {
          case 'minute':
          case 'minutes':
            return job.dueAt.add(Duration(minutes: amount));
          case 'hour':
          case 'hours':
            return job.dueAt.add(Duration(hours: amount));
          case 'day':
          case 'days':
            return job.dueAt.add(Duration(days: amount));
          case 'week':
          case 'weeks':
            return job.dueAt.add(Duration(days: amount * 7));
        }
      }
    }

    // Try parsing as ISO 8601 duration
    if (rule.startsWith('p') || rule.startsWith('P')) {
      // Parse PT1H, P1D, etc.
      try {
        final hoursMatch = RegExp(r'(\d+)H', caseSensitive: false)
            .firstMatch(rule);
        final minutesMatch = RegExp(r'(\d+)M', caseSensitive: false)
            .firstMatch(rule);
        final daysMatch = RegExp(r'(\d+)D', caseSensitive: false)
            .firstMatch(rule);
        var next = job.dueAt;
        if (daysMatch != null) {
          next = next.add(Duration(days: int.parse(daysMatch.group(1)!)));
        }
        if (hoursMatch != null) {
          next = next.add(Duration(hours: int.parse(hoursMatch.group(1)!)));
        }
        if (minutesMatch != null) {
          next = next.add(
              Duration(minutes: int.parse(minutesMatch.group(1)!)));
        }
        if (next != job.dueAt) return next;
      } catch (_) {}
    }

    return null;
  }
}
