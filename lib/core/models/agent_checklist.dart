import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'agent_checklist.g.dart';

@HiveType(typeId: 20)
enum ChecklistOwnerType {
  @HiveField(0)
  assistant,
  @HiveField(1)
  team,
  @HiveField(2)
  workspace,
  @HiveField(3)
  user,
}

@HiveType(typeId: 21)
enum ChecklistVisibility {
  @HiveField(0)
  @HiveField(0)
  private,
  @HiveField(1)
  shared,
  @HiveField(2)
  team,
}

@HiveType(typeId: 22)
enum DoubleCheckMode {
  @HiveField(0)
  sameAgentAllowed,
  @HiveField(1)
  differentAgentRequired,
  @HiveField(2)
  leaderMustApproveSecondPass,
  @HiveField(3)
  userMustApproveFinalPass,
}

@HiveType(typeId: 23)
enum ChecklistPermission {
  @HiveField(0)
  read,
  @HiveField(1)
  write,
  @HiveField(2)
  verify,
  @HiveField(3)
  approve,
  @HiveField(4)
  admin,
}

@HiveType(typeId: 24)
class ChecklistAccessGrant extends HiveObject {
  @HiveField(0)
  final String principalType; // assistant, team, user

  @HiveField(1)
  final String principalId;

  @HiveField(2)
  final List<String> permissions; // serialized ChecklistPermission names

  ChecklistAccessGrant({
    required this.principalType,
    required this.principalId,
    required this.permissions,
  });

  Map<String, dynamic> toJson() => {
    'principalType': principalType,
    'principalId': principalId,
    'permissions': permissions,
  };

  factory ChecklistAccessGrant.fromJson(Map<String, dynamic> json) =>
      ChecklistAccessGrant(
        principalType: json['principalType'] as String,
        principalId: json['principalId'] as String,
        permissions: (json['permissions'] as List).cast<String>(),
      );
}

@HiveType(typeId: 25)
class AgentChecklist extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String description;

  @HiveField(3)
  final ChecklistOwnerType ownerType;

  @HiveField(4)
  final String ownerId;

  @HiveField(5)
  final List<ChecklistAccessGrant> accessGrants;

  @HiveField(6)
  final DateTime createdAt;

  @HiveField(7)
  DateTime updatedAt;

  @HiveField(8)
  final bool archived;

  @HiveField(9)
  final ChecklistVisibility visibility;

  @HiveField(10)
  final DoubleCheckMode validationPolicy;

  @HiveField(11)
  final int requiredConsecutivePasses; // default 2

  AgentChecklist({
    String? id,
    required this.title,
    this.description = '',
    required this.ownerType,
    required this.ownerId,
    List<ChecklistAccessGrant>? accessGrants,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.archived = false,
    this.visibility = ChecklistVisibility.private,
    this.validationPolicy = DoubleCheckMode.sameAgentAllowed,
    this.requiredConsecutivePasses = 2,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       accessGrants = accessGrants ?? [];

  AgentChecklist copyWith({
    String? title,
    String? description,
    List<ChecklistAccessGrant>? accessGrants,
    DateTime? updatedAt,
    bool? archived,
    ChecklistVisibility? visibility,
    DoubleCheckMode? validationPolicy,
    int? requiredConsecutivePasses,
  }) {
    return AgentChecklist(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      ownerType: ownerType,
      ownerId: ownerId,
      accessGrants: accessGrants ?? this.accessGrants,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      archived: archived ?? this.archived,
      visibility: visibility ?? this.visibility,
      validationPolicy: validationPolicy ?? this.validationPolicy,
      requiredConsecutivePasses:
          requiredConsecutivePasses ?? this.requiredConsecutivePasses,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'ownerType': ownerType.name,
    'ownerId': ownerId,
    'accessGrants': accessGrants.map((g) => g.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'archived': archived,
    'visibility': visibility.name,
    'validationPolicy': validationPolicy.name,
    'requiredConsecutivePasses': requiredConsecutivePasses,
  };

  factory AgentChecklist.fromJson(Map<String, dynamic> json) => AgentChecklist(
    id: json['id'] as String,
    title: json['title'] as String,
    description: (json['description'] as String?) ?? '',
    ownerType: ChecklistOwnerType.values.firstWhere(
      (e) => e.name == json['ownerType'],
      orElse: () => ChecklistOwnerType.assistant,
    ),
    ownerId: json['ownerId'] as String,
    accessGrants: (json['accessGrants'] as List?)
            ?.map((e) =>
                ChecklistAccessGrant.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    archived: json['archived'] as bool? ?? false,
    visibility: ChecklistVisibility.values.firstWhere(
      (e) => e.name == json['visibility'],
      orElse: () => ChecklistVisibility.private,
    ),
    validationPolicy: DoubleCheckMode.values.firstWhere(
      (e) => e.name == json['validationPolicy'],
      orElse: () => DoubleCheckMode.sameAgentAllowed,
    ),
    requiredConsecutivePasses:
        (json['requiredConsecutivePasses'] as num?)?.toInt() ?? 2,
  );
}