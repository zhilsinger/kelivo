class ChatItem {
  final String id;
  final String title;
  final DateTime created;
  final bool isSubtask;
  final int taskStatus;

  ChatItem({
    required this.id,
    required this.title,
    required this.created,
    this.isSubtask = false,
    this.taskStatus = 0,
  });

  ChatItem copyWith({
    String? id,
    String? title,
    DateTime? created,
    bool? isSubtask,
    int? taskStatus,
  }) =>
      ChatItem(
        id: id ?? this.id,
        title: title ?? this.title,
        created: created ?? this.created,
        isSubtask: isSubtask ?? this.isSubtask,
        taskStatus: taskStatus ?? this.taskStatus,
      );
}
