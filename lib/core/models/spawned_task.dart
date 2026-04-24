/// Task status constants for spawned sub-tasks.
class TaskStatus {
  TaskStatus._();

  /// The sub-task has been created but not yet started.
  static const int pending = 0;

  /// The sub-task is actively being processed.
  static const int inProgress = 1;

  /// The sub-task has completed successfully.
  static const int completed = 2;

  /// The sub-task needs clarification or additional input.
  static const int needsClarification = 3;

  /// The sub-task encountered an error.
  static const int error = 4;

  /// Human-readable label for a task status.
  static String label(int status) {
    switch (status) {
      case pending:
        return 'pending';
      case inProgress:
        return 'in_progress';
      case completed:
        return 'completed';
      case needsClarification:
        return 'needs_clarification';
      case error:
        return 'error';
      default:
        return 'unknown';
    }
  }
}
