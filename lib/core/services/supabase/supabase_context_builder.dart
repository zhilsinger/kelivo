import '../../models/supabase_memory_context.dart';

/// Builds the final AI memory context block from search results.
///
/// This is a PURE formatting class. No state, no Dio, no Supabase.
/// Responsibilities:
/// - Filter chunks by memory mode
/// - Apply token budget
/// - Deduplicate chunks from the same message
/// - Format into a prompt-ready XML block
/// - Estimate token count
class SupabaseContextBuilder {
  static const int defaultMaxChunks = 8;
  static const int defaultMaxTokens = 2000;
  static const int charsPerTokenEstimate = 4;

  /// Build a context package from raw search results.
  AiMemoryContextPackage build({
    required List<SupabaseMemoryChunk> chunks,
    required SupabaseMemoryMode mode,
    required String? currentConversationId,
    int maxChunks = defaultMaxChunks,
    int maxTokens = defaultMaxTokens,
    Set<String>? pinnedMemoryIds,
  }) {
    if (chunks.isEmpty) return AiMemoryContextPackage.empty;

    // 1. Filter by mode
    var filtered = _filterByMode(chunks, mode, currentConversationId);

    // 2. Deduplicate — same message → keep highest score
    filtered = _deduplicateByMessage(filtered);

    // 3. Apply budget
    filtered = _applyBudget(filtered, maxChunks, maxTokens);

    if (filtered.isEmpty) return AiMemoryContextPackage.empty;

    // 4. Format block
    final formatted = _formatBlock(filtered);
    final estimatedTokens = formatted.length ~/ charsPerTokenEstimate;

    // 5. Build sources for preview
    final sources = filtered.map((c) {
      return MemoryContextSource(
        threadTitle: c.threadTitle,
        threadId: c.threadId,
        messageDate: c.messageDate,
        relevanceScore: c.similarityScore,
        snippet: c.content.length > 120
            ? '${c.content.substring(0, 120)}...'
            : c.content,
      );
    }).toList();

    return AiMemoryContextPackage(
      formattedBlock: formatted,
      sources: sources,
      estimatedTokens: estimatedTokens,
      chunkCount: filtered.length,
    );
  }

  // ── Mode filter ──────────────────────────────────────────────────────

  List<SupabaseMemoryChunk> _filterByMode(
    List<SupabaseMemoryChunk> chunks,
    SupabaseMemoryMode mode,
    String? currentConversationId,
  ) {
    switch (mode) {
      case SupabaseMemoryMode.off:
        return [];
      case SupabaseMemoryMode.currentThread:
        if (currentConversationId == null) return [];
        return chunks
            .where((c) => c.threadId == currentConversationId)
            .toList();
      case SupabaseMemoryMode.allArchives:
        return List.of(chunks);
      case SupabaseMemoryMode.pinnedOnly:
      case SupabaseMemoryMode.project:
        // Project filtering requires Phase 8; fall through to all for now.
        return List.of(chunks);
    }
  }

  // ── Deduplication ────────────────────────────────────────────────────

  List<SupabaseMemoryChunk> _deduplicateByMessage(
    List<SupabaseMemoryChunk> chunks,
  ) {
    final seen = <String, SupabaseMemoryChunk>{};
    for (final c in chunks) {
      final existing = seen[c.messageId];
      if (existing == null || c.similarityScore > existing.similarityScore) {
        seen[c.messageId] = c;
      }
    }
    return seen.values.toList();
  }

  // ── Budget ───────────────────────────────────────────────────────────

  List<SupabaseMemoryChunk> _applyBudget(
    List<SupabaseMemoryChunk> chunks,
    int maxChunks,
    int maxTokens,
  ) {
    final sorted = List<SupabaseMemoryChunk>.of(chunks)
      ..sort((a, b) => b.similarityScore.compareTo(a.similarityScore));

    final result = <SupabaseMemoryChunk>[];
    int tokenTotal = 0;

    for (final c in sorted) {
      if (result.length >= maxChunks) break;
      final est = c.content.length ~/ charsPerTokenEstimate;
      if (tokenTotal + est > maxTokens && result.isNotEmpty) break;
      result.add(c);
      tokenTotal += est;
    }

    return result;
  }

  // ── Formatting ───────────────────────────────────────────────────────

  String _formatBlock(List<SupabaseMemoryChunk> chunks) {
    final buf = StringBuffer();
    buf.writeln('<supabase_memory>');
    buf.writeln(
      'The following are relevant memories from your conversation history:',
    );
    for (final c in chunks) {
      final date = c.messageDate.toIso8601String().substring(0, 10);
      buf.writeln(
        '<memory_chunk thread="${_escape(c.threadTitle)}" '
        'date="$date" '
        'relevance="${c.similarityScore.toStringAsFixed(2)}">',
      );
      buf.writeln(c.content);
      buf.writeln('</memory_chunk>');
    }
    buf.writeln('</supabase_memory>');
    return buf.toString();
  }

  String _escape(String s) {
    return s.replaceAll('"', '&quot;').replaceAll('<', '&lt;');
  }
}
