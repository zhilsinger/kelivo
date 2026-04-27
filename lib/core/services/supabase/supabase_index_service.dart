import 'dart:convert';
import 'supabase_chunk_service.dart';
import 'supabase_client_service.dart';

/// Indexes synced messages into Supabase message_chunks for full-text search.
/// Called by SyncOrchestrator after each successful thread sync.
class SupabaseIndexService {
  final SupabaseClientService _client;
  final SupabaseChunkService _chunker;

  SupabaseIndexService({
    SupabaseClientService? client,
    SupabaseChunkService? chunker,
  })  : _client = client ?? SupabaseClientService.instance,
        _chunker = chunker ?? SupabaseChunkService();

  /// Index all messages for a synced thread.
  /// Messages must include: id, role, content, created_at (ISO 8601 string).
  /// These fields come from ChatMessage.toSupabaseJson().
  Future<int> indexThread({
    required String threadId,
    required String threadTitle,
    required List<Map<String, dynamic>> messages,
  }) async {
    if (!_client.isConfigured) return 0;

    int totalChunks = 0;

    for (int msgIdx = 0; msgIdx < messages.length; msgIdx++) {
      final msg = messages[msgIdx];
      final content = (msg['content'] as String?) ?? '';
      if (content.trim().isEmpty) continue;

      final role = (msg['role'] as String?) ?? 'unknown';
      final createdAt = msg['created_at'] as String?;
      final messageId = (msg['id'] as String?) ?? '';

      // 1. Chunk the raw content (no metadata enrichment in chunk_text)
      final chunks = _chunker.chunkMessage(content);

      // 2. Check for duplicates by hash
      final hashes = chunks.map((c) => c.chunkHash).toList();
      final existingHashes = await _fetchExistingHashes(hashes);
      final newChunks = chunks.where(
        (c) => !existingHashes.contains(c.chunkHash),
      ).toList();

      if (newChunks.isEmpty) continue;

      // 3. Insert new chunks (one at a time with error handling)
      for (final chunk in newChunks) {
        try {
          await _client.rpc('upsert_message_chunk', params: {
            'p_user_id': _client.userId ?? '',
            'p_thread_id': threadId,
            'p_message_id': messageId,
            'p_chunk_index': chunk.chunkIndex,
            'p_chunk_text': chunk.chunkText,
            'p_chunk_hash': chunk.chunkHash,
            'p_token_estimate': chunk.tokenEstimate,
            'p_source_thread_title': threadTitle,
            'p_source_message_role': role,
            'p_source_created_at': createdAt,
            'p_source_position': msgIdx,
            'p_chunker_version': 'kelivo_chunker_v1',
          });
          totalChunks++;
        } catch (_) {
          // Best-effort: skip failed chunk insert, continue with next
        }
      }
    }

    return totalChunks;
  }

  /// Fetch existing chunk hashes to avoid duplicates.
  Future<Set<String>> _fetchExistingHashes(List<String> hashes) async {
    if (hashes.isEmpty) return {};
    try {
      final result = await _client.rpc('check_chunk_hashes', params: {
        'p_hashes': hashes,
        'p_user_id': _client.userId ?? '',
      });
      if (result is List) {
        return result.map((r) => r.toString()).toSet();
      }
      return {};
    } catch (_) {
      return {};
    }
  }
}