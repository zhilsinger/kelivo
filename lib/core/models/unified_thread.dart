import 'package:hive/hive.dart';

part 'unified_thread.g.dart';

@HiveType(typeId: 20)
class UnifiedThread extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  final String source; // 'chatgpt', 'gemini', 'perplexity', 'claude', 'kelivo', 'other'

  @HiveField(3)
  final List<UnifiedMessage> messages;

  @HiveField(4)
  final DateTime createdAt;

  @HiveField(5)
  DateTime updatedAt;

  @HiveField(6)
  final bool syncedToCloud;

  UnifiedThread({
    required this.id,
    required this.title,
    required this.source,
    required this.messages,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncedToCloud = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  UnifiedThread copyWith({
    String? id,
    String? title,
    String? source,
    List<UnifiedMessage>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? syncedToCloud,
  }) =>
      UnifiedThread(
        id: id ?? this.id,
        title: title ?? this.title,
        source: source ?? this.source,
        messages: messages ?? this.messages,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        syncedToCloud: syncedToCloud ?? this.syncedToCloud,
      );

  @override
  String toString() => 'UnifiedThread(id: $id, title: $title, source: $source, messages: ${messages.length})';

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'source': source,
    'messages': messages.map((m) => m.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'syncedToCloud': syncedToCloud,
  };

  factory UnifiedThread.fromJson(Map<String, dynamic> json) => UnifiedThread(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    source: json['source'] as String? ?? 'other',
    messages: (json['messages'] as List? ?? [])
        .map((m) => UnifiedMessage.fromJson(m as Map<String, dynamic>))
        .toList(),
    createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : null,
    updatedAt: json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : null,
    syncedToCloud: json['syncedToCloud'] as bool? ?? false,
  );
}

@HiveType(typeId: 21)
class UnifiedMessage extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String role; // 'user', 'assistant', 'system'

  @HiveField(2)
  String content;

  @HiveField(3)
  final DateTime createdAt;

  @HiveField(4)
  Map<String, dynamic>? metadata;

  UnifiedMessage({
    required this.id,
    required this.role,
    required this.content,
    DateTime? createdAt,
    this.metadata,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    if (metadata != null) 'metadata': metadata,
  };

  factory UnifiedMessage.fromJson(Map<String, dynamic> json) => UnifiedMessage(
    id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
    role: json['role'] as String? ?? 'user',
    content: json['content'] as String? ?? '',
    createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : null,
    metadata: json['metadata'] as Map<String, dynamic>?,
  );

  @override
  String toString() => 'UnifiedMessage(id: $id, role: $role)';
}
