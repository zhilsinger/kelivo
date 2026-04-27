import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

/// Supported sync operations.
enum SyncOperation { upsert, delete }

/// Supported entity types for sync.
enum SyncEntityType { thread, message }

/// A single job in the sync queue, persisted in Hive.
@HiveType(typeId: 100)
class SyncJob extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String entityType; // 'thread' or 'message'

  @HiveField(2)
  final String entityId;

  @HiveField(3)
  final String operation; // 'upsert' or 'delete'

  @HiveField(4)
  final String? payloadJson; // serialised map (only for upsert, null for deletes)

  @HiveField(5)
  int retryCount;

  @HiveField(6)
  String? lastError;

  @HiveField(7)
  final DateTime createdAt;

  SyncJob({
    String? id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    this.payloadJson,
    this.retryCount = 0,
    this.lastError,
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  SyncJob copyWith({
    String? id,
    String? entityType,
    String? entityId,
    String? operation,
    String? payloadJson,
    int? retryCount,
    String? lastError,
    DateTime? createdAt,
  }) =>
      SyncJob(
        id: id ?? this.id,
        entityType: entityType ?? this.entityType,
        entityId: entityId ?? this.entityId,
        operation: operation ?? this.operation,
        payloadJson: payloadJson ?? this.payloadJson,
        retryCount: retryCount ?? this.retryCount,
        lastError: lastError ?? this.lastError,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'entityType': entityType,
    'entityId': entityId,
    'operation': operation,
    'payloadJson': payloadJson,
    'retryCount': retryCount,
    'lastError': lastError,
    'createdAt': createdAt.toIso8601String(),
  };

  factory SyncJob.fromJson(Map<String, dynamic> json) => SyncJob(
    id: json['id'] as String,
    entityType: json['entityType'] as String,
    entityId: json['entityId'] as String,
    operation: json['operation'] as String,
    payloadJson: json['payloadJson'] as String?,
    retryCount: json['retryCount'] as int? ?? 0,
    lastError: json['lastError'] as String?,
    createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : null,
  );
}

/// Hive adapter for SyncJob (typeId 100).
class SyncJobAdapter extends TypeAdapter<SyncJob> {
  @override
  final int typeId = 100;

  @override
  SyncJob read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numFields; i++) {
      final tag = reader.readByte();
      final value = reader.read();
      fields[tag] = value;
    }
    return SyncJob(
      id: fields[0] as String,
      entityType: fields[1] as String,
      entityId: fields[2] as String,
      operation: fields[3] as String,
      payloadJson: fields[4] as String?,
      retryCount: fields[5] as int? ?? 0,
      lastError: fields[6] as String?,
      createdAt: fields[7] != null
          ? DateTime.fromMillisecondsSinceEpoch(fields[7] as int)
          : null,
    );
  }

  @override
  void write(BinaryWriter writer, SyncJob obj) {
    writer.writeByte(8);
    writer.writeByte(0);
    writer.write(obj.id);
    writer.writeByte(1);
    writer.write(obj.entityType);
    writer.writeByte(2);
    writer.write(obj.entityId);
    writer.writeByte(3);
    writer.write(obj.operation);
    writer.writeByte(4);
    writer.write(obj.payloadJson);
    writer.writeByte(5);
    writer.write(obj.retryCount);
    writer.writeByte(6);
    writer.write(obj.lastError);
    writer.writeByte(7);
    writer.write(obj.createdAt.millisecondsSinceEpoch);
  }
}
