import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo/core/services/supabase/supabase_conflict_resolver.dart';
import 'package:kelivo/core/models/supabase_sync_conflict.dart';

void main() {
  final baseTime = DateTime(2026, 4, 1);
  const resolver = SupabaseConflictResolver();

  group('SupabaseConflictResolver', () {
    test('remote tombstoned, local present -> takeRemote', () {
      final result = resolver.resolve(
        local: ThreadSyncState(
          threadId: 't1', isDeleted: false,
          updatedAt: baseTime, messageCount: 3, contentHash: 'abc',
          title: 'Local',
        ),
        remote: ThreadSyncState(
          threadId: 't1', isDeleted: true,
          updatedAt: baseTime, messageCount: 3, contentHash: 'abc',
          title: 'Remote (deleted)',
        ),
      );
      expect(result.outcome, ConflictOutcome.takeRemote);
    });

    test('local deleted, remote present -> takeRemote (restore)', () {
      final result = resolver.resolve(
        local: ThreadSyncState(
          threadId: 't1', isDeleted: true,
          updatedAt: baseTime, messageCount: 0, contentHash: '',
          title: '',
        ),
        remote: ThreadSyncState(
          threadId: 't1', isDeleted: false,
          updatedAt: baseTime, messageCount: 5, contentHash: 'xyz',
          title: 'Remote',
        ),
      );
      expect(result.outcome, ConflictOutcome.takeRemote);
    });

    test('remote newer -> merge', () {
      final result = resolver.resolve(
        local: ThreadSyncState(
          threadId: 't1', isDeleted: false,
          updatedAt: baseTime, messageCount: 3, contentHash: 'old',
          title: 'Old',
        ),
        remote: ThreadSyncState(
          threadId: 't1', isDeleted: false,
          updatedAt: baseTime.add(const Duration(hours: 1)),
          messageCount: 5, contentHash: 'new',
          title: 'New',
        ),
      );
      expect(result.outcome, ConflictOutcome.merge);
    });

    test('local newer -> keepLocal', () {
      final result = resolver.resolve(
        local: ThreadSyncState(
          threadId: 't1', isDeleted: false,
          updatedAt: baseTime.add(const Duration(hours: 2)),
          messageCount: 3, contentHash: 'newer',
          title: 'Newer',
        ),
        remote: ThreadSyncState(
          threadId: 't1', isDeleted: false,
          updatedAt: baseTime,
          messageCount: 3, contentHash: 'older',
          title: 'Older',
        ),
      );
      expect(result.outcome, ConflictOutcome.keepLocal);
    });

    test('equal timestamps, diverged content -> manualReview', () {
      final result = resolver.resolve(
        local: ThreadSyncState(
          threadId: 't1', isDeleted: false,
          updatedAt: baseTime, messageCount: 3, contentHash: 'abc',
          title: 'Local',
        ),
        remote: ThreadSyncState(
          threadId: 't1', isDeleted: false,
          updatedAt: baseTime, messageCount: 5, contentHash: 'xyz',
          title: 'Remote',
        ),
      );
      expect(result.outcome, ConflictOutcome.manualReview);
    });

    test('identical state -> keepLocal (no conflict)', () {
      final result = resolver.resolve(
        local: ThreadSyncState(
          threadId: 't1', isDeleted: false,
          updatedAt: baseTime, messageCount: 3, contentHash: 'abc',
          title: 'Same',
        ),
        remote: ThreadSyncState(
          threadId: 't1', isDeleted: false,
          updatedAt: baseTime, messageCount: 3, contentHash: 'abc',
          title: 'Same',
        ),
      );
      expect(result.outcome, ConflictOutcome.keepLocal);
    });
  });
}
