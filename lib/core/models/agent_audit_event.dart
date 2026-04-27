import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'agent_audit_event.g.dart';

@HiveType(typeId: 29)
class AgentAuditEvent extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String entityType; // checklist, item, timer, workspace, team

  @HiveField(2)
  final String entityId;

  @HiveField(3)
  final String action;

  @HiveField(4)
  final String actorId;

  @HiveField(5)
  final String actorName;

  @HiveField(6)
  final String actorType;

  @HiveField(7)
  final DateTime createdAt;

  @HiveField(8)
  final String beforeJson; // JSON-encoded state before change

  @HiveField(9)
  final String afterJson; // JSON-encoded state after change

  @HiveField(10)
  final String? reason;

  @HiveField(11)
  final String? conversationId;

  @HiveField(12)
  final String? messageId;

  AgentAuditEvent({
    String? id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.actorId,
    required this.actorName,
    required this.actorType,
    DateTime? createdAt,
    this.beforeJson = '{}',
    this.afterJson = '{}',
    this.reason,
    this.conversationId,
    this.messageId,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'entityType': entityType,
    'entityId': entityId,
    'action': action,
    'actorId': actorId,
    'actorName': actorName,
    'actorType': actorType,
    'createdAt': createdAt.toIso8601String(),
    'beforeJson': beforeJson,
    'afterJson': afterJson,
    'reason': reason,
    'conversationId': conversationId,
    'messageId': messageId,
  };

  factory AgentAuditEvent.fromJson(Map<String, dynamic> json) =>
      AgentAuditEvent(
        id: json['id'] as String,
        entityType: json['entityType'] as String,
        entityId: json['entityId'] as String,
        action: json['action'] as String,
        actorId: json['actorId'] as String,
        actorName: json['actorName'] as String,
        actorType: json['actorType'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        beforeJson: (json['beforeJson'] as String?) ?? '{}',
        afterJson: (json['afterJson'] as String?) ?? '{}',
        reason: json['reason'] as String?,
        conversationId: json['conversationId'] as String?,
        messageId: json['messageId'] as String?,
      );
}