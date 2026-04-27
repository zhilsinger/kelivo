import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'agent_timer_job.g.dart';

@HiveType(typeId: 30)
enum TimerStatus {
  @HiveField(0)
  scheduled,
  @HiveField(1)
  firing,
  @HiveField(2)
  fired,
  @HiveField(3)
  completed,
  @HiveField(4)
  cancelled,
  @HiveField(5)
  failed,
  @HiveField(6)
  missed,
}

@HiveType(typeId: 31)
class AgentTimerJob extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String prompt;

  @HiveField(3)
  final String targetAssistantId;

  @HiveField(4)
  final String? targetTeamId;

  @HiveField(5)
  final String? targetConversationId;

  @HiveField(6)
  final String? targetChecklistId;

  @HiveField(7)
  final String? targetChecklistItemId;

  @HiveField(8)
  final DateTime createdAt;

  @HiveField(9)
  final DateTime dueAt;

  @HiveField(10)
  TimerStatus status;

  @HiveField(11)
  final String createdByActorId;

  @HiveField(12)
  final String createdByActorType;

  @HiveField(13)
  final bool userVisible;

  @HiveField(14)
  final bool notifyUser;

  @HiveField(15)
  final String? recurrenceRule;

  @HiveField(16)
  final int? maxRuns;

  @HiveField(17)
  int runCount;

  @HiveField(18)
  final DateTime? lastFiredAt;

  @HiveField(19)
  final DateTime? completedAt;

  /// MCP server IDs that were active when this timer was created.
  @HiveField(20)
  final List<String> mcpServerIds;

  AgentTimerJob({
    String? id,
    required this.title,
    required this.prompt,
    required this.targetAssistantId,
    this.targetTeamId,
    this.targetConversationId,
    this.targetChecklistId,
    this.targetChecklistItemId,
    DateTime? createdAt,
    required this.dueAt,
    this.status = TimerStatus.scheduled,
    required this.createdByActorId,
    this.createdByActorType = 'assistant',
    this.userVisible = true,
    this.notifyUser = true,
    this.recurrenceRule,
    this.maxRuns,
    this.runCount = 0,
    this.lastFiredAt,
    this.completedAt,
    List<String>? mcpServerIds,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       mcpServerIds = mcpServerIds ?? [];

  AgentTimerJob copyWith({
    String? title,
    String? prompt,
    DateTime? dueAt,
    TimerStatus? status,
    String? targetConversationId,
    int? runCount,
    DateTime? lastFiredAt,
    DateTime? completedAt,
  }) {
    return AgentTimerJob(
      id: id,
      title: title ?? this.title,
      prompt: prompt ?? this.prompt,
      targetAssistantId: targetAssistantId,
      targetTeamId: targetTeamId,
      targetConversationId: targetConversationId ?? this.targetConversationId,
      targetChecklistId: targetChecklistId,
      targetChecklistItemId: targetChecklistItemId,
      createdAt: createdAt,
      dueAt: dueAt ?? this.dueAt,
      status: status ?? this.status,
      createdByActorId: createdByActorId,
      createdByActorType: createdByActorType,
      userVisible: userVisible,
      notifyUser: notifyUser,
      recurrenceRule: recurrenceRule,
      maxRuns: maxRuns,
      runCount: runCount ?? this.runCount,
      lastFiredAt: lastFiredAt ?? this.lastFiredAt,
      completedAt: completedAt ?? this.completedAt,
      mcpServerIds: mcpServerIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'prompt': prompt,
    'targetAssistantId': targetAssistantId,
    'targetTeamId': targetTeamId,
    'targetConversationId': targetConversationId,
    'targetChecklistId': targetChecklistId,
    'targetChecklistItemId': targetChecklistItemId,
    'createdAt': createdAt.toIso8601String(),
    'dueAt': dueAt.toIso8601String(),
    'status': status.name,
    'createdByActorId': createdByActorId,
    'createdByActorType': createdByActorType,
    'userVisible': userVisible,
    'notifyUser': notifyUser,
    'recurrenceRule': recurrenceRule,
    'maxRuns': maxRuns,
    'runCount': runCount,
    'lastFiredAt': lastFiredAt?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'mcpServerIds': mcpServerIds,
  };

  factory AgentTimerJob.fromJson(Map<String, dynamic> json) => AgentTimerJob(
    id: json['id'] as String,
    title: json['title'] as String,
    prompt: json['prompt'] as String,
    targetAssistantId: json['targetAssistantId'] as String,
    targetTeamId: json['targetTeamId'] as String?,
    targetConversationId: json['targetConversationId'] as String?,
    targetChecklistId: json['targetChecklistId'] as String?,
    targetChecklistItemId: json['targetChecklistItemId'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    dueAt: DateTime.parse(json['dueAt'] as String),
    status: TimerStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => TimerStatus.scheduled,
    ),
    createdByActorId: json['createdByActorId'] as String,
    createdByActorType: (json['createdByActorType'] as String?) ?? 'assistant',
    userVisible: json['userVisible'] as bool? ?? true,
    notifyUser: json['notifyUser'] as bool? ?? true,
    recurrenceRule: json['recurrenceRule'] as String?,
    maxRuns: (json['maxRuns'] as num?)?.toInt(),
    runCount: (json['runCount'] as num?)?.toInt() ?? 0,
    lastFiredAt: json['lastFiredAt'] != null
        ? DateTime.parse(json['lastFiredAt'] as String)
        : null,
    completedAt: json['completedAt'] != null
        ? DateTime.parse(json['completedAt'] as String)
        : null,
    mcpServerIds:
        (json['mcpServerIds'] as List?)?.cast<String>() ?? [],
  );
}