import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'agent_checklist_item.g.dart';

@HiveType(typeId: 26)
enum ChecklistItemStatus {
  @HiveField(0)
  open,
  @HiveField(1)
  inProgress,
  @HiveField(2)
  blocked,
  @HiveField(3)
  verificationPending,
  @HiveField(4)
  passedOnce,
  @HiveField(5)
  completed,
  @HiveField(6)
  failed,
  @HiveField(7)
  skipped,
  @HiveField(8)
  archived,
}

@HiveType(typeId: 27)
class AgentChecklistItem extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String checklistId;

  @HiveField(2)
  final String title;

  @HiveField(3)
  final String instructions;

  @HiveField(4)
  final String acceptanceCriteria;

  @HiveField(5)
  ChecklistItemStatus status;

  @HiveField(6)
  final int orderIndex;

  @HiveField(7)
  int requiredConsecutivePasses;

  @HiveField(8)
  final List<String> dependencyItemIds;

  @HiveField(9)
  final String? assignedAssistantId;

  @HiveField(10)
  final String? assignedTeamId;

  @HiveField(11)
  final DateTime createdAt;

  @HiveField(12)
  DateTime updatedAt;

  @HiveField(13)
  final String? completedByActorId;

  @HiveField(14)
  final String? completedByActorName;

  @HiveField(15)
  final String? completedByActorType;

  @HiveField(16)
  final DateTime? completedAt;

  @HiveField(17)
  final String? completionSummary;

  @HiveField(18)
  final List<String> evidenceRefs;

  /// Current revision hash for verification matching.
  @HiveField(19)
  String currentRevisionHash;

  AgentChecklistItem({
    String? id,
    required this.checklistId,
    required this.title,
    this.instructions = '',
    this.acceptanceCriteria = '',
    this.status = ChecklistItemStatus.open,
    required this.orderIndex,
    this.requiredConsecutivePasses = 2,
    List<String>? dependencyItemIds,
    this.assignedAssistantId,
    this.assignedTeamId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.completedByActorId,
    this.completedByActorName,
    this.completedByActorType,
    this.completedAt,
    this.completionSummary,
    List<String>? evidenceRefs,
    String? currentRevisionHash,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       dependencyItemIds = dependencyItemIds ?? [],
       evidenceRefs = evidenceRefs ?? [],
       currentRevisionHash = currentRevisionHash ?? _computeHash();

  static String _computeHash() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  void bumpRevision() {
    currentRevisionHash = DateTime.now().microsecondsSinceEpoch.toString();
  }

  AgentChecklistItem copyWith({
    String? title,
    String? instructions,
    String? acceptanceCriteria,
    ChecklistItemStatus? status,
    int? orderIndex,
    int? requiredConsecutivePasses,
    List<String>? dependencyItemIds,
    String? assignedAssistantId,
    String? assignedTeamId,
    DateTime? updatedAt,
    String? completedByActorId,
    String? completedByActorName,
    String? completedByActorType,
    DateTime? completedAt,
    String? completionSummary,
    List<String>? evidenceRefs,
    String? currentRevisionHash,
    bool clearAssignment = false,
    bool clearCompletion = false,
  }) {
    return AgentChecklistItem(
      id: id,
      checklistId: checklistId,
      title: title ?? this.title,
      instructions: instructions ?? this.instructions,
      acceptanceCriteria: acceptanceCriteria ?? this.acceptanceCriteria,
      status: status ?? this.status,
      orderIndex: orderIndex ?? this.orderIndex,
      requiredConsecutivePasses:
          requiredConsecutivePasses ?? this.requiredConsecutivePasses,
      dependencyItemIds: dependencyItemIds ?? this.dependencyItemIds,
      assignedAssistantId: clearAssignment
          ? null
          : (assignedAssistantId ?? this.assignedAssistantId),
      assignedTeamId:
          clearAssignment ? null : (assignedTeamId ?? this.assignedTeamId),
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      completedByActorId:
          clearCompletion ? null : (completedByActorId ?? this.completedByActorId),
      completedByActorName: clearCompletion
          ? null
          : (completedByActorName ?? this.completedByActorName),
      completedByActorType: clearCompletion
          ? null
          : (completedByActorType ?? this.completedByActorType),
      completedAt: clearCompletion ? null : (completedAt ?? this.completedAt),
      completionSummary:
          clearCompletion ? null : (completionSummary ?? this.completionSummary),
      evidenceRefs: evidenceRefs ?? this.evidenceRefs,
      currentRevisionHash: currentRevisionHash ?? this.currentRevisionHash,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'checklistId': checklistId,
    'title': title,
    'instructions': instructions,
    'acceptanceCriteria': acceptanceCriteria,
    'status': status.name,
    'orderIndex': orderIndex,
    'requiredConsecutivePasses': requiredConsecutivePasses,
    'dependencyItemIds': dependencyItemIds,
    'assignedAssistantId': assignedAssistantId,
    'assignedTeamId': assignedTeamId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'completedByActorId': completedByActorId,
    'completedByActorName': completedByActorName,
    'completedByActorType': completedByActorType,
    'completedAt': completedAt?.toIso8601String(),
    'completionSummary': completionSummary,
    'evidenceRefs': evidenceRefs,
    'currentRevisionHash': currentRevisionHash,
  };

  factory AgentChecklistItem.fromJson(Map<String, dynamic> json) =>
      AgentChecklistItem(
        id: json['id'] as String,
        checklistId: json['checklistId'] as String,
        title: json['title'] as String,
        instructions: (json['instructions'] as String?) ?? '',
        acceptanceCriteria: (json['acceptanceCriteria'] as String?) ?? '',
        status: ChecklistItemStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => ChecklistItemStatus.open,
        ),
        orderIndex: (json['orderIndex'] as num?)?.toInt() ?? 0,
        requiredConsecutivePasses:
            (json['requiredConsecutivePasses'] as num?)?.toInt() ?? 2,
        dependencyItemIds:
            (json['dependencyItemIds'] as List?)?.cast<String>() ?? [],
        assignedAssistantId: json['assignedAssistantId'] as String?,
        assignedTeamId: json['assignedTeamId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        completedByActorId: json['completedByActorId'] as String?,
        completedByActorName: json['completedByActorName'] as String?,
        completedByActorType: json['completedByActorType'] as String?,
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
        completionSummary: json['completionSummary'] as String?,
        evidenceRefs: (json['evidenceRefs'] as List?)?.cast<String>() ?? [],
        currentRevisionHash: (json['currentRevisionHash'] as String?) ?? '',
      );
}