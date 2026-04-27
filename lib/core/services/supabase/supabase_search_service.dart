import 'supabase_client_service.dart';

/// A single search result from the FTS search.
class ChunkSearchResult {
  final String chunkId;
  final String threadId;
  final String? messageId;
  final int chunkIndex;
  final String chunkText;
  final String? threadTitle;
  final String? messageRole;
  final DateTime? sourceCreatedAt;
  final double rank;

  const ChunkSearchResult({
    required this.chunkId,
    required this.threadId,
    this.messageId,
    required this.chunkIndex,
    required this.chunkText,
    this.threadTitle,
    this.messageRole,
    this.sourceCreatedAt,
    required this.rank,
  });

  factory ChunkSearchResult.fromMap(Map<String, dynamic> map) {
    return ChunkSearchResult(
      chunkId: map['chunk_id']?.toString() ?? '',
      threadId: map['thread_id']?.toString() ?? '',
      messageId: map['message_id']?.toString(),
      chunkIndex: (map['chunk_index'] as num?)?.toInt() ?? 0,
      chunkText: map['chunk_text']?.toString() ?? '',
      threadTitle: map['source_thread_title']?.toString(),
      messageRole: map['source_message_role']?.toString(),
      sourceCreatedAt: map['source_created_at'] != null
          ? DateTime.tryParse(map['source_created_at'].toString())
          : null,
      rank: (map['rank'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class SupabaseSearchService {
  final SupabaseClientService _client;

  SupabaseSearchService({SupabaseClientService? client})
      : _client = client ?? SupabaseClientService.instance;

  /// Full-text search on message chunks via search_message_chunks_fts RPC.
  Future<List<ChunkSearchResult>> search({
    required String query,
    int limit = 20,
  }) async {
    if (!_client.isConfigured) return [];
    if (query.trim().isEmpty) return [];

    try {
      final result = await _client.rpc('search_message_chunks_fts', params: {
        'search_query': query.trim(),
        'target_user_id': _client.userId ?? '',
        'match_limit': limit,
      });

      if (result is List) {
        return result
            .whereType<Map>()
            .map((m) => ChunkSearchResult.fromMap(
                  (m as Map).cast<String, dynamic>(),
                ))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}