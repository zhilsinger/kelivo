enum CloudMemorySource {
  local,
  supabase,
}

enum CloudMemoryType {
  preference,
  project,
  decision,
  todo,
  technicalDetail,
  errorSolution,
}

/// Sidecar metadata for AssistantMemory records.
///
/// Stored separately from the frozen [AssistantMemory] model
/// (Extension-by-Addition Rule). Keyed by [memoryId].
class CloudMemoryMetadata {
  final int memoryId;
  final CloudMemorySource source;
  final String? sourceThreadId;
  final String? sourceMessageId;
  final int memoryScore; // 0–5
  final CloudMemoryType memoryType;
  final bool pinned;
  final bool reviewed;
  final DateTime createdAt;
  final DateTime lastAccessedAt;
  final int accessCount;
  final int? decayAfterDays;
  final bool stale;

  const CloudMemoryMetadata({
    required this.memoryId,
    this.source = CloudMemorySource.local,
    this.sourceThreadId,
    this.sourceMessageId,
    this.memoryScore = 0,
    this.memoryType = CloudMemoryType.preference,
    this.pinned = false,
    this.reviewed = false,
    required this.createdAt,
    required this.lastAccessedAt,
    this.accessCount = 0,
    this.decayAfterDays,
    this.stale = false,
  });

  CloudMemoryMetadata copyWith({
    int? memoryId,
    CloudMemorySource? source,
    String? sourceThreadId,
    bool clearSourceThreadId = false,
    String? sourceMessageId,
    bool clearSourceMessageId = false,
    int? memoryScore,
    CloudMemoryType? memoryType,
    bool? pinned,
    bool? reviewed,
    DateTime? createdAt,
    DateTime? lastAccessedAt,
    int? accessCount,
    int? decayAfterDays,
    bool clearDecayAfterDays = false,
    bool? stale,
  }) {
    return CloudMemoryMetadata(
      memoryId: memoryId ?? this.memoryId,
      source: source ?? this.source,
      sourceThreadId:
          clearSourceThreadId ? null : (sourceThreadId ?? this.sourceThreadId),
      sourceMessageId: clearSourceMessageId
          ? null
          : (sourceMessageId ?? this.sourceMessageId),
      memoryScore: memoryScore ?? this.memoryScore,
      memoryType: memoryType ?? this.memoryType,
      pinned: pinned ?? this.pinned,
      reviewed: reviewed ?? this.reviewed,
      createdAt: createdAt ?? this.createdAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      accessCount: accessCount ?? this.accessCount,
      decayAfterDays:
          clearDecayAfterDays ? null : (decayAfterDays ?? this.decayAfterDays),
      stale: stale ?? this.stale,
    );
  }

  Map<String, dynamic> toJson() => {
        'memoryId': memoryId,
        'source': source.name,
        'sourceThreadId': sourceThreadId,
        'sourceMessageId': sourceMessageId,
        'memoryScore': memoryScore,
        'memoryType': memoryType.name,
        'pinned': pinned,
        'reviewed': reviewed,
        'createdAt': createdAt.toIso8601String(),
        'lastAccessedAt': lastAccessedAt.toIso8601String(),
        'accessCount': accessCount,
        'decayAfterDays': decayAfterDays,
        'stale': stale,
      };

  factory CloudMemoryMetadata.fromJson(Map<String, dynamic> json) {
    return CloudMemoryMetadata(
      memoryId: (json['memoryId'] as num).toInt(),
      source: _parseSource(json['source']),
      sourceThreadId: json['sourceThreadId'] as String?,
      sourceMessageId: json['sourceMessageId'] as String?,
      memoryScore: (json['memoryScore'] as num?)?.toInt() ?? 0,
      memoryType: _parseType(json['memoryType']),
      pinned: json['pinned'] as bool? ?? false,
      reviewed: json['reviewed'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastAccessedAt: DateTime.parse(json['lastAccessedAt'] as String),
      accessCount: (json['accessCount'] as num?)?.toInt() ?? 0,
      decayAfterDays: (json['decayAfterDays'] as num?)?.toInt(),
      stale: json['stale'] as bool? ?? false,
    );
  }

  static CloudMemorySource _parseSource(dynamic value) {
    final s = (value ?? '').toString();
    for (final e in CloudMemorySource.values) {
      if (e.name == s) return e;
    }
    return CloudMemorySource.local;
  }

  static CloudMemoryType _parseType(dynamic value) {
    final s = (value ?? '').toString();
    for (final e in CloudMemoryType.values) {
      if (e.name == s) return e;
    }
    return CloudMemoryType.preference;
  }
}
