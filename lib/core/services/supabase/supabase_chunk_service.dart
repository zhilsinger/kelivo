import 'dart:convert';
import 'package:crypto/crypto.dart';

/// A single chunk produced by the chunker.
class MessageChunk {
  final int chunkIndex;
  final String chunkText;
  final String chunkHash;   // SHA-256 hex string for dedup
  final int tokenEstimate;  // char count / 4 (rough estimate)

  const MessageChunk({
    required this.chunkIndex,
    required this.chunkText,
    required this.chunkHash,
    required this.tokenEstimate,
  });
}

/// Chunking configuration.
class ChunkConfig {
  /// Target chunk size in characters (middle of 3000-5000 range).
  final int targetSize;

  /// Overlap between adjacent chunks in characters (middle of 300-500 range).
  final int overlap;

  /// Minimum chunk size — below this, don't split further.
  final int minChunkSize;

  const ChunkConfig({
    this.targetSize = 4000,
    this.overlap = 400,
    this.minChunkSize = 500,
  });
}

class SupabaseChunkService {
  final ChunkConfig _config;

  SupabaseChunkService({ChunkConfig? config})
      : _config = config ?? const ChunkConfig();

  /// Split content into one or more overlapping chunks.
  /// - Preserves code block boundaries (``` fences).
  /// - Splits at sentence/phrase boundaries.
  /// - Returns single-element list if content fits in one chunk.
  List<MessageChunk> chunkMessage(String content) {
    if (content.isEmpty) return [];

    if (content.length <= _config.targetSize) {
      return [_makeChunk(0, content)];
    }

    final codeBlockRanges = _findCodeBlocks(content);
    final chunks = <MessageChunk>[];
    int start = 0;
    int index = 0;

    while (start < content.length) {
      int end = start + _config.targetSize;
      if (end >= content.length) {
        final text = content.substring(start).trim();
        if (text.isNotEmpty) {
          chunks.add(_makeChunk(index, text));
        }
        break;
      }

      // Don't split inside a code block
      final adjustedEnd = _adjustForCodeBlocks(end, codeBlockRanges);
      if (adjustedEnd != null) {
        end = adjustedEnd;
      } else {
        end = _findSentenceBoundary(content, start, end);
      }

      final text = content.substring(start, end).trim();
      if (text.isNotEmpty) {
        chunks.add(_makeChunk(index, text));
        index++;
      }

      // Next chunk starts with overlap
      start = (end - _config.overlap).clamp(0, content.length);
      if (start >= end) start = end; // guard against infinite loop
    }

    return chunks;
  }

  /// Find all code block ranges (between ``` fences).
  List<_Range> _findCodeBlocks(String content) {
    final ranges = <_Range>[];
    final regex = RegExp(r'^```', multiLine: true);
    final matches = regex.allMatches(content).toList();

    for (int i = 0; i < matches.length - 1; i += 2) {
      final start = matches[i].start;
      final end = matches[i + 1].end;
      ranges.add(_Range(start, end));
    }
    return ranges;
  }

  /// If [position] falls inside a code block, return the nearest safe boundary.
  int? _adjustForCodeBlocks(int position, List<_Range> codeBlocks) {
    for (final block in codeBlocks) {
      if (position > block.start && position < block.end) {
        if (position - block.start < block.end - position) {
          return block.start;
        } else {
          return block.end;
        }
      }
    }
    return null;
  }

  /// Find the nearest sentence/phrase boundary before [maxEnd].
  int _findSentenceBoundary(String content, int start, int maxEnd) {
    final searchStart = (maxEnd - 200).clamp(start, maxEnd);
    final substring = content.substring(searchStart, maxEnd);

    // Preferred boundaries, in priority order
    final boundaries = [
      RegExp(r'[.!?]\s'),
      RegExp(r'\n\n'),
      RegExp(r'\n'),
      RegExp(r'[;:]\s'),
      RegExp(r',\s'),
    ];

    for (final pattern in boundaries) {
      final matches = pattern.allMatches(substring);
      if (matches.isNotEmpty) {
        return searchStart + matches.last.end;
      }
    }

    // Fallback: split at last space
    final lastSpace = substring.lastIndexOf(' ');
    if (lastSpace > 0) return searchStart + lastSpace;

    return maxEnd;
  }

  MessageChunk _makeChunk(int index, String text) {
    final hash = sha256.convert(utf8.encode(text)).toString();
    return MessageChunk(
      chunkIndex: index,
      chunkText: text,                  // raw content only, no metadata header
      chunkHash: hash,
      tokenEstimate: (text.length / 4).ceil(),
    );
  }
}

class _Range {
  final int start;
  final int end;
  const _Range(this.start, this.end);
}