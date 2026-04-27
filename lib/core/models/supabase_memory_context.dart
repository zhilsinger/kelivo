/// The result of building AI memory context from Supabase search results.
class AiMemoryContextPackage {
  /// Ready-to-inject XML block for the system prompt.
  final String formattedBlock;

  /// Sources for the preview widget.
  final List<MemoryContextSource> sources;

  /// Estimated token count (content.length ~/ 4).
  final int estimatedTokens;

  /// Number of chunks included.
  final int chunkCount;

  const AiMemoryContextPackage({
    required this.formattedBlock,
    required this.sources,
    required this.estimatedTokens,
    required this.chunkCount,
  });

  bool get isEmpty => formattedBlock.isEmpty;

  static const AiMemoryContextPackage empty = AiMemoryContextPackage(
    formattedBlock: '',
    sources: [],
    estimatedTokens: 0,
    chunkCount: 0,
  );
}

/// Metadata for a single memory source shown in the preview.
class MemoryContextSource {
  final String threadTitle;
  final String threadId;
  final DateTime messageDate;
  final double relevanceScore;
  final String snippet;

  const MemoryContextSource({
    required this.threadTitle,
    required this.threadId,
    required this.messageDate,
    required this.relevanceScore,
    required this.snippet,
  });
}

/// Memory search mode for Supabase AI memory.
enum SupabaseMemoryMode {
  /// No memory injection.
  off,

  /// Only the current conversation.
  currentThread,

  /// Current project (future: Phase 8).
  project,

  /// All synced threads.
  allArchives,

  /// Only pinned memories.
  pinnedOnly,
}

/// A memory chunk returned from Supabase AI memory search.
/// This is the interface contract that Phase 4 (SupabaseAiMemoryService)
/// must satisfy.
class SupabaseMemoryChunk {
  final String content;
  final String threadTitle;
  final String threadId;
  final DateTime messageDate;
  final double similarityScore;
  final String messageId;

  const SupabaseMemoryChunk({
    required this.content,
    required this.threadTitle,
    required this.threadId,
    required this.messageDate,
    required this.similarityScore,
    required this.messageId,
  });
}
