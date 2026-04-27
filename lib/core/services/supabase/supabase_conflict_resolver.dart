import '../../models/supabase_sync_conflict.dart';

/// Pure-logic conflict resolver for sync comparisons.
/// Zero I/O, zero dependencies. Fully testable in isolation.

/// Represents a thread's state at a point in time, either locally or remotely.
class ThreadSyncState {
  final String threadId;
  final String title;
  final DateTime updatedAt;
  final int messageCount;
  final String? lastMessageId;
  final bool isDeleted;
  final String contentHash;

  const ThreadSyncState({
    required this.threadId,
    required this.title,
    required this.updatedAt,
    required this.messageCount,
    this.lastMessageId,
    this.isDeleted = false,
    required this.contentHash,
  });

  factory ThreadSyncState.fromConversation(Conversation c) => ThreadSyncState(
    threadId: c.id,
    title: c.title,
    updatedAt: c.updatedAt,
    messageCount: c.messageIds.length,
    lastMessageId: c.messageIds.isNotEmpty ? c.messageIds.last : null,
    contentHash: c.updatedAt.millisecondsSinceEpoch.toString(),
  );

  factory ThreadSyncState.fromRemoteMap(Map<String, dynamic> map) {
    final deletedAt = map['deleted_at'] as String?;
    return ThreadSyncState(
      threadId: map['id'] as String,
      title: (map['title'] as String?) ?? '',
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : DateTime.now(),
      messageCount: (map['message_count'] as int?) ?? 0,
      lastMessageId: map['last_message_id'] as String?,
      isDeleted: deletedAt != null && deletedAt.isNotEmpty,
      contentHash: (map['content_hash'] as String?) ?? '',
    );
  }
}

/// Outcome of a conflict resolution attempt.
enum ConflictOutcome { keepLocal, takeRemote, merge, manualReview }

/// Result returned by SupabaseConflictResolver.
class ConflictResolutionResult {
  final ConflictOutcome outcome;
  final String reason;
  final SyncConflict? conflict;

  const ConflictResolutionResult({
    required this.outcome,
    required this.reason,
    this.conflict,
  });
}

/// Compares local vs remote thread state and returns a resolution decision.
///
/// Resolution rules (priority order):
/// 1. Remote tombstoned + local present -> takeRemote (delete local)
/// 2. Local deleted + remote present  -> takeRemote (restore from remote)
/// 3. Remote updatedAt is newer       -> merge (append remote messages)
/// 4. Local updatedAt is newer        -> keepLocal
/// 5. Equal timestamps, diverged      -> manualReview
class SupabaseConflictResolver {
  const SupabaseConflictResolver();

  ConflictResolutionResult resolve({
    required ThreadSyncState local,
    required ThreadSyncState remote,
  }) {
    // Rule 1: remote tombstoned
    if (remote.isDeleted && !local.isDeleted) {
      return const ConflictResolutionResult(
        outcome: ConflictOutcome.takeRemote,
        reason: 'Remote thread was deleted (tombstoned).',
      );
    }

    // Rule 2: local deleted, remote present
    if (local.isDeleted && !remote.isDeleted) {
      return const ConflictResolutionResult(
        outcome: ConflictOutcome.takeRemote,
        reason: 'Local thread was deleted — restoring from remote.',
      );
    }

    // Rule 3: remote is newer -> merge
    if (remote.updatedAt.isAfter(local.updatedAt)) {
      return const ConflictResolutionResult(
        outcome: ConflictOutcome.merge,
        reason: 'Remote has newer changes — merging.',
      );
    }

    // Rule 4: local is newer -> keep local
    if (local.updatedAt.isAfter(remote.updatedAt)) {
      return const ConflictResolutionResult(
        outcome: ConflictOutcome.keepLocal,
        reason: 'Local has newer changes.',
      );
    }

    // Rule 5: equal timestamps, check for divergence
    if (local.contentHash != remote.contentHash) {
      return const ConflictResolutionResult(
        outcome: ConflictOutcome.manualReview,
        reason: 'Equal timestamps but content diverged — manual review required.',
      );
    }

    // No conflict: identical state
    return const ConflictResolutionResult(
      outcome: ConflictOutcome.keepLocal,
      reason: 'State is identical — no conflict.',
    );
  }
}

// Import needed for ThreadSyncState.fromConversation factory
import '../../../models/conversation.dart';
