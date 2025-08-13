enum TodoStatus { pending, doing, done, blocked }

class Todo {
  String eventId;
  String description;
  TodoStatus status;
  DateTime createdAt;

  Todo({
    required this.eventId,
    required this.description,
    required this.createdAt,
    this.status = TodoStatus.pending,
  });

  bool get isCompleted => status == TodoStatus.done;
}
