/// Pure data classes for sync conflict records.
/// Stored on Supabase, not locally. JSON-serializable for REST transport.

enum ConflictType {
  localDeletedRemotePresent,
  remoteDeletedLocalPresent,
  bothUpdated,
  messageDivergence,
  tombstoneMismatch,
}

/// A single sync conflict record.
/// No Hive annotations — conflicts live on Supabase, not in local storage.
class SyncConflict {
  final String id;
  final String threadId;
  final ConflictType type;
  final Map<String, dynamic> localState;
  final Map<String, dynamic> remoteState;
  final DateTime detectedAt;
  final bool resolved;
  final String? resolution;
  final DateTime? resolvedAt;

  const SyncConflict({
    required this.id,
    required this.threadId,
    required this.type,
    required this.localState,
    required this.remoteState,
    required this.detectedAt,
    this.resolved = false,
    this.resolution,
    this.resolvedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': '',
    'thread_id': threadId,
    'conflict_type': type.name,
    'local_state': localState,
    'remote_state': remoteState,
    'detected_at': detectedAt.toUtc().toIso8601String(),
    'resolved': resolved,
    'resolution': resolution,
    'resolved_at': resolvedAt?.toUtc().toIso8601String(),
  };

  factory SyncConflict.fromJson(Map<String, dynamic> json) => SyncConflict(
    id: json['id'] as String,
    threadId: json['thread_id'] as String,
    type: ConflictType.values.firstWhere(
      (t) => t.name == json['conflict_type'],
      orElse: () => ConflictType.bothUpdated,
    ),
    localState: (json['local_state'] as Map?)?.cast<String, dynamic>() ?? {},
    remoteState: (json['remote_state'] as Map?)?.cast<String, dynamic>() ?? {},
    detectedAt: DateTime.parse(json['detected_at'] as String),
    resolved: json['resolved'] as bool? ?? false,
    resolution: json['resolution'] as String?,
    resolvedAt: json['resolved_at'] != null
        ? DateTime.parse(json['resolved_at'] as String)
        : null,
  );

  SyncConflict copyWith({
    String? id,
    String? threadId,
    ConflictType? type,
    Map<String, dynamic>? localState,
    Map<String, dynamic>? remoteState,
    DateTime? detectedAt,
    bool? resolved,
    String? resolution,
    DateTime? resolvedAt,
  }) => SyncConflict(
    id: id ?? this.id,
    threadId: threadId ?? this.threadId,
    type: type ?? this.type,
    localState: localState ?? this.localState,
    remoteState: remoteState ?? this.remoteState,
    detectedAt: detectedAt ?? this.detectedAt,
    resolved: resolved ?? this.resolved,
    resolution: resolution ?? this.resolution,
    resolvedAt: resolvedAt ?? this.resolvedAt,
  );
}
