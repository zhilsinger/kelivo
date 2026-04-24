import '../../../core/services/supabase/supabase_client_service.dart';
import '../../../core/models/unified_thread.dart';

class SupabaseThreadSyncResult {
  final bool success;
  final String? error;

  const SupabaseThreadSyncResult({required this.success, this.error});
}

class SupabaseThreadSyncService {
  final SupabaseClientService _client;

  SupabaseThreadSyncService(this._client);

  bool get isConfigured => _client.isConfigured;

  /// Push a single thread + all its messages to Supabase
  Future<SupabaseThreadSyncResult> pushThread(UnifiedThread thread) async {
    if (!_client.isConfigured) {
      return const SupabaseThreadSyncResult(
        success: false,
        error: 'Supabase not configured',
      );
    }

    try {
      await _client.syncThread(
        id: thread.id,
        title: thread.title,
        source: thread.source,
        createdAt: thread.createdAt,
        updatedAt: thread.updatedAt,
        messages: thread.messages.map((m) => {
          'id': m.id,
          'thread_id': thread.id,
          'role': m.role,
          'content': m.content,
          'created_at': m.createdAt.toUtc().toIso8601String(),
          if (m.metadata != null) 'metadata': m.metadata,
        }).toList(),
      );
      return const SupabaseThreadSyncResult(success: true);
    } catch (e) {
      return SupabaseThreadSyncResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Delete a thread from Supabase
  Future<SupabaseThreadSyncResult> deleteThread(String threadId) async {
    if (!_client.isConfigured) {
      return const SupabaseThreadSyncResult(
        success: false,
        error: 'Supabase not configured',
      );
    }

    try {
      await _client.deleteThread(threadId);
      return const SupabaseThreadSyncResult(success: true);
    } catch (e) {
      return SupabaseThreadSyncResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Pull all threads from Supabase
  Future<SupabaseThreadSyncResult> pullAllThreads() async {
    if (!_client.isConfigured) {
      return const SupabaseThreadSyncResult(
        success: false,
        error: 'Supabase not configured',
      );
    }

    try {
      final threadsData = await _client.fetchThreads();
      final threads = <UnifiedThread>[];
      for (final td in threadsData) {
        final messagesData = await _client.fetchMessages(td['id'] as String);
        threads.add(UnifiedThread(
          id: td['id'] as String,
          title: td['title'] as String? ?? '',
          source: td['source'] as String? ?? 'other',
          createdAt: DateTime.parse(td['created_at'] as String),
          updatedAt: DateTime.parse(td['updated_at'] as String),
          messages: messagesData.map((m) => UnifiedMessage(
            id: m['id'] as String,
            role: m['role'] as String? ?? 'user',
            content: m['content'] as String? ?? '',
            createdAt: DateTime.parse(m['created_at'] as String),
          )).toList(),
          syncedToCloud: true,
        ));
      }
      return SupabaseThreadSyncResult(
        success: true,
      ).._threads = threads;
    } catch (e) {
      return SupabaseThreadSyncResult(
        success: false,
        error: e.toString(),
      );
    }
  }
}

// Extension to carry data on the result
extension _ThreadResultExt on SupabaseThreadSyncResult {
  List<UnifiedThread>? _threads;
  List<UnifiedThread>? get threads => _threads;
}

SupabaseThreadSyncResult _pullResult(List<UnifiedThread> threads) {
  final result = SupabaseThreadSyncResult(success: true);
  result._threads = threads;
  return result;
}
