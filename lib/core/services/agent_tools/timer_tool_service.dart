import '../../models/agent_timer_job.dart';
import '../../models/agent_actor.dart';
import '../agent_timer/agent_timer_service.dart';

/// Tool definitions for agent timer operations exposed to LLMs.
///
/// Agents can schedule, list, and cancel timers. When a timer fires,
/// the agent is prompted with the stored message in [TIMER_TRIGGER] tags.
class TimerToolService {
  final AgentTimerService _timerService;

  TimerToolService({required AgentTimerService timerService})
      : _timerService = timerService;

  /// Check if a tool call name belongs to the timer domain.
  bool isTimerTool(String name) {
    switch (name) {
      case 'set_timer':
      case 'list_timers':
      case 'cancel_timer':
      case 'get_timer_status':
        return true;
      default:
        return false;
    }
  }

  /// Build the tool definitions for the timer domain.
  List<Map<String, dynamic>> buildToolDefinitions() {
    return [
      _setTimerDef(),
      _listTimersDef(),
      _cancelTimerDef(),
      _getTimerStatusDef(),
    ];
  }

  /// Route a tool call to the appropriate handler.
  Future<String> call({
    required AgentActor actor,
    required String name,
    required Map<String, dynamic> args,
  }) async {
    switch (name) {
      case 'set_timer':
        return _handleSetTimer(actor, args);
      case 'list_timers':
        return _handleListTimers();
      case 'cancel_timer':
        return _handleCancelTimer(args);
      case 'get_timer_status':
        return _handleGetTimerStatus(args);
      default:
        return 'Unknown timer tool: $name';
    }
  }

  // ─── Tool definitions ────────────────────────────────────────────

  Map<String, dynamic> _setTimerDef() => {
        'type': 'function',
        'function': {
          'name': 'set_timer',
          'description':
              'Set a timer that will send a message to you at the specified time. '
              'When the timer fires, you will receive the prompt as a new message '
              'marked with [TIMER_TRIGGER] tags. Use this for reminders, '
              'follow-ups, or deferred task checks.',
          'parameters': {
            'type': 'object',
            'properties': {
              'title': {
                'type': 'string',
                'description': 'Short label for this timer',
              },
              'prompt': {
                'type': 'string',
                'description':
                    'The message to send back when the timer fires. Be specific '
                    'about what you want to check or do at that time.',
              },
              'due_at': {
                'type': 'string',
                'description':
                    'ISO 8601 timestamp when the timer should fire (e.g. '
                    '2026-04-27T12:00:00Z). Use UTC.',
              },
              'recurrence': {
                'type': 'string',
                'description':
                    'Optional recurrence rule. Examples: "every 10 minutes", '
                    '"every 1 hour", "every 1 day", or ISO 8601 duration like '
                    '"PT1H" (every hour), "P1D" (every day)',
              },
              'max_runs': {
                'type': 'integer',
                'description':
                    'Maximum number of times this timer should fire (only for recurring timers)',
              },
              'checklist_id': {
                'type': 'string',
                'description':
                    'If this timer is related to a specific checklist, provide its ID',
              },
              'checklist_item_id': {
                'type': 'string',
                'description':
                    'If this timer is related to a specific checklist item, provide its ID',
              },
            },
            'required': ['title', 'prompt', 'due_at'],
          },
        },
      };

  Map<String, dynamic> _listTimersDef() => {
        'type': 'function',
        'function': {
          'name': 'list_timers',
          'description': 'List all active timers',
          'parameters': {
            'type': 'object',
            'properties': {},
          },
        },
      };

  Map<String, dynamic> _cancelTimerDef() => {
        'type': 'function',
        'function': {
          'name': 'cancel_timer',
          'description': 'Cancel an active timer',
          'parameters': {
            'type': 'object',
            'properties': {
              'timer_id': {
                'type': 'string',
                'description': 'ID of the timer to cancel',
              },
            },
            'required': ['timer_id'],
          },
        },
      };

  Map<String, dynamic> _getTimerStatusDef() => {
        'type': 'function',
        'function': {
          'name': 'get_timer_status',
          'description': 'Get the current status and details of a timer',
          'parameters': {
            'type': 'object',
            'properties': {
              'timer_id': {
                'type': 'string',
                'description': 'ID of the timer to check',
              },
            },
            'required': ['timer_id'],
          },
        },
      };

  // ─── Tool handlers ───────────────────────────────────────────────

  Future<String> _handleSetTimer(
      AgentActor actor, Map<String, dynamic> args) async {
    final title = args['title'] as String;
    final prompt = args['prompt'] as String;
    final dueAtStr = args['due_at'] as String;
    final recurrence = args['recurrence'] as String?;
    final maxRuns = (args['max_runs'] as num?)?.toInt();
    final checklistId = args['checklist_id'] as String?;
    final checklistItemId = args['checklist_item_id'] as String?;

    DateTime dueAt;
    try {
      dueAt = DateTime.parse(dueAtStr);
    } catch (_) {
      return 'Invalid due_at format. Use ISO 8601 (e.g., 2026-04-27T12:00:00Z)';
    }

    if (dueAt.isBefore(DateTime.now())) {
      return 'Cannot set a timer in the past. due_at must be in the future.';
    }

    final job = await _timerService.scheduleTimer(
      title: title,
      prompt: prompt,
      targetAssistantId: actor.id,
      dueAt: dueAt,
      createdByActorId: actor.id,
      createdByActorType: actor.type.name,
      recurrenceRule: recurrence,
      maxRuns: maxRuns,
      targetChecklistId: checklistId,
      targetChecklistItemId: checklistItemId,
    );

    final remaining = dueAt.difference(DateTime.now());
    final remainingStr = _formatDuration(remaining);

    var result = 'Timer set (id: ${job.id}). Will fire in $remainingStr '
        'at ${dueAt.toIso8601String()}';
    if (recurrence != null) {
      result += ' (recurring: $recurrence)';
    }
    return result;
  }

  Future<String> _handleListTimers() async {
    final active = await _timerService.getActiveTimers();
    final missed = await _timerService.getMissedTimers();

    if (active.isEmpty && missed.isEmpty) {
      return 'No active or missed timers.';
    }

    final sb = StringBuffer();
    if (active.isNotEmpty) {
      sb.writeln('Active timers:');
      for (final t in active) {
        final remaining = t.dueAt.difference(DateTime.now());
        final remainingStr = _formatDuration(remaining);
        sb.writeln(
            '- ${t.title} (id: ${t.id}, fires in $remainingStr, '
            'run ${t.runCount}/${t.maxRuns?.toString() ?? '∞'})');
      }
    }
    if (missed.isNotEmpty) {
      if (active.isNotEmpty) sb.writeln();
      sb.writeln('Missed timers:');
      for (final t in missed) {
        sb.writeln('- ${t.title} (id: ${t.id}, was due at ${t.dueAt.toIso8601String()})');
      }
    }
    return sb.toString().trim();
  }

  Future<String> _handleCancelTimer(Map<String, dynamic> args) async {
    final timerId = args['timer_id'] as String;
    // Check if timer exists
    final all = await _timerService.getAllTimers();
    final job = all.where((t) => t.id == timerId).firstOrNull;
    if (job == null) return 'Timer $timerId not found';
    if (job.status == TimerStatus.cancelled) {
      return 'Timer ${job.title} (id: $timerId) is already cancelled';
    }

    await _timerService.cancelTimer(timerId);
    return 'Timer "${job.title}" (id: $timerId) cancelled';
  }

  Future<String> _handleGetTimerStatus(Map<String, dynamic> args) async {
    final timerId = args['timer_id'] as String;
    final all = await _timerService.getAllTimers();
    final job = all.where((t) => t.id == timerId).firstOrNull;
    if (job == null) return 'Timer $timerId not found';

    final remaining = job.dueAt.difference(DateTime.now());
    final sb = StringBuffer();
    sb.writeln('Timer: ${job.title} (id: ${job.id})');
    sb.writeln('Status: ${job.status.name}');
    sb.writeln('Due: ${job.dueAt.toIso8601String()}');
    if (job.status == TimerStatus.scheduled && !remaining.isNegative) {
      sb.writeln('Remaining: ${_formatDuration(remaining)}');
    }
    sb.writeln('Runs: ${job.runCount}/${job.maxRuns?.toString() ?? '∞'}');
    if (job.recurrenceRule != null) {
      sb.writeln('Recurrence: ${job.recurrenceRule}');
    }
    if (job.lastFiredAt != null) {
      sb.writeln('Last fired: ${job.lastFiredAt!.toIso8601String()}');
    }
    sb.writeln('Prompt: ${job.prompt}');
    return sb.toString().trim();
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return 'overdue';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }
}
