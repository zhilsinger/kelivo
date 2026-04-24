import 'package:uuid/uuid.dart';
import 'chat_input_data.dart';

/// A single item in the multi-item, persistent prompt queue.
///
/// This is a SEPARATE model from [QueuedChatInput] which is the
/// old single-item transient queue. Both systems coexist independently.
class PromptQueueItem {
  final String id; // uuid
  final String conversationId;
  final ChatInputData input;
  final int position; // order index in queue
  final DateTime createdAt;
  final String? assistantId;

  PromptQueueItem({
    required this.id,
    required this.conversationId,
    required this.input,
    required this.position,
    required this.createdAt,
    this.assistantId,
  });

  PromptQueueItem copyWith({
    String? id,
    String? conversationId,
    ChatInputData? input,
    int? position,
    DateTime? createdAt,
    String? assistantId,
  }) =>
      PromptQueueItem(
        id: id ?? this.id,
        conversationId: conversationId ?? this.conversationId,
        input: input ?? this.input,
        position: position ?? this.position,
        createdAt: createdAt ?? this.createdAt,
        assistantId: assistantId ?? this.assistantId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'text': input.text,
        'imagePaths': input.imagePaths,
        'documents': input.documents
            .map((d) => {
                  'path': d.path,
                  'fileName': d.fileName,
                  'mime': d.mime,
                })
            .toList(),
        'position': position,
        'createdAt': createdAt.toIso8601String(),
        'assistantId': assistantId,
      };

  factory PromptQueueItem.fromJson(Map<String, dynamic> json) {
    final docs = (json['documents'] as List?)
            ?.map((d) => DocumentAttachment(
                  path: d['path'] as String? ?? '',
                  fileName: d['fileName'] as String? ?? '',
                  mime: d['mime'] as String? ?? '',
                ))
            .toList() ??
        [];
    return PromptQueueItem(
      id: json['id'] as String? ?? const Uuid().v4(),
      conversationId: json['conversationId'] as String? ?? '',
      input: ChatInputData(
        text: json['text'] as String? ?? '',
        imagePaths: (json['imagePaths'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        documents: docs,
      ),
      position: json['position'] as int? ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      assistantId: json['assistantId'] as String?,
    );
  }
}
