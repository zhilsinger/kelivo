import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'agent_check_result.g.dart';

@HiveType(typeId: 28)
class AgentCheckResult extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String checklistId;

  @HiveField(2)
  final String itemId;

  @HiveField(3)
  final String actorId;

  @HiveField(4)
  final String actorName;

  @HiveField(5)
  final String actorType;

  @HiveField(6)
  final DateTime checkedAt;

  @HiveField(7)
  final bool passed;

  @HiveField(8)
  final int confidencePercent; // 100 for auto-complete

  @HiveField(9)
  final String summary;

  @HiveField(10)
  final List<String> issuesFound;

  @HiveField(11)
  final List<String> evidenceRefs;

  @HiveField(12)
  final String itemRevisionHash;

  @HiveField(13)
  final int sequenceNumber;

  AgentCheckResult({
    String? id,
    required this.checklistId,
    required this.itemId,
    required this.actorId,
    required this.actorName,
    required this.actorType,
    DateTime? checkedAt,
    required this.passed,
    this.confidencePercent = 0,
    this.summary = '',
    List<String>? issuesFound,
    List<String>? evidenceRefs,
    required this.itemRevisionHash,
    required this.sequenceNumber,
  }) : id = id ?? const Uuid().v4(),
       checkedAt = checkedAt ?? DateTime.now(),
       issuesFound = issuesFound ?? [],
       evidenceRefs = evidenceRefs ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'checklistId': checklistId,
    'itemId': itemId,
    'actorId': actorId,
    'actorName': actorName,
    'actorType': actorType,
    'checkedAt': checkedAt.toIso8601String(),
    'passed': passed,
    'confidencePercent': confidencePercent,
    'summary': summary,
    'issuesFound': issuesFound,
    'evidenceRefs': evidenceRefs,
    'itemRevisionHash': itemRevisionHash,
    'sequenceNumber': sequenceNumber,
  };

  factory AgentCheckResult.fromJson(Map<String, dynamic> json) =>
      AgentCheckResult(
        id: json['id'] as String,
        checklistId: json['checklistId'] as String,
        itemId: json['itemId'] as String,
        actorId: json['actorId'] as String,
        actorName: json['actorName'] as String,
        actorType: json['actorType'] as String,
        checkedAt: DateTime.parse(json['checkedAt'] as String),
        passed: json['passed'] as bool,
        confidencePercent: (json['confidencePercent'] as num?)?.toInt() ?? 0,
        summary: (json['summary'] as String?) ?? '',
        issuesFound: (json['issuesFound'] as List?)?.cast<String>() ?? [],
        evidenceRefs: (json['evidenceRefs'] as List?)?.cast<String>() ?? [],
        itemRevisionHash: json['itemRevisionHash'] as String,
        sequenceNumber: (json['sequenceNumber'] as num?)?.toInt() ?? 0,
      );
}