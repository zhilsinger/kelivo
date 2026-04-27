import 'chat_input_data.dart';

enum QueueItemSource { user, sideAssistant }

class PromptQueueItem {
  final String id;
  final String conversationId;
  final ChatInputData input;
  final QueueItemSource source;
  final String? sideChatNote;
  final DateTime createdAt;
  final int order;

  PromptQueueItem({
    required this.id,
    required this.conversationId,
    required this.input,
    this.source = QueueItemSource.user,
    this.sideChatNote,
    required this.createdAt,
    required this.order,
  });

  PromptQueueItem copyWith({
    String? id,
    String? conversationId,
    ChatInputData? input,
    QueueItemSource? source,
    String? sideChatNote,
    DateTime? createdAt,
    int? order,
  }) =>
      PromptQueueItem(
        id: id ?? this.id,
        conversationId: conversationId ?? this.conversationId,
        input: input ?? this.input,
        source: source ?? this.source,
        sideChatNote: sideChatNote ?? this.sideChatNote,
        createdAt: createdAt ?? this.createdAt,
        order: order ?? this.order,
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
        'source': source.name,
        'sideChatNote': sideChatNote,
        'createdAt': createdAt.toIso8601String(),
        'order': order,
      };

  factory PromptQueueItem.fromJson(Map<String, dynamic> json) {
    final docs = (json['documents'] as List?)
            ?.map((d) => DocumentAttachment(
                  path: (d['path'] ?? '').toString(),
                  fileName: (d['fileName'] ?? '').toString(),
                  mime: (d['mime'] ?? '').toString(),
                ))
            .toList() ??
        [];
    return PromptQueueItem(
      id: (json['id'] ?? '').toString(),
      conversationId: (json['conversationId'] ?? '').toString(),
      input: ChatInputData(
        text: (json['text'] ?? '').toString(),
        imagePaths: (json['imagePaths'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        documents: docs,
      ),
      source: _parseQueueItemSource(json['source'] as String?),
      sideChatNote: json['sideChatNote'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      order: (json['order'] as int?) ?? 0,
    );
  }

  static QueueItemSource _parseQueueItemSource(String? s) {
    if (s == 'sideAssistant') return QueueItemSource.sideAssistant;
    return QueueItemSource.user;
  }
}
