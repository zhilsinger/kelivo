import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cloud_memory_metadata.dart';

/// Persists [CloudMemoryMetadata] records using a separate
/// SharedPreferences key (`cloud_memory_metadata_v1`).
///
/// This is a sidecar store — it never touches the frozen
/// [AssistantMemory] model or its [MemoryStore].
class CloudMemoryMetadataStore {
  static const String _key = 'cloud_memory_metadata_v1';

  static Map<int, CloudMemoryMetadata>? _cache;

  static Future<Map<int, CloudMemoryMetadata>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <int, CloudMemoryMetadata>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return <int, CloudMemoryMetadata>{};
      final result = <int, CloudMemoryMetadata>{};
      for (final entry in decoded.entries) {
        final id = int.tryParse(entry.key);
        if (id == null) continue;
        if (entry.value is Map<String, dynamic>) {
          result[id] = CloudMemoryMetadata.fromJson(
            entry.value as Map<String, dynamic>,
          );
        }
      }
      return result;
    } catch (_) {
      return <int, CloudMemoryMetadata>{};
    }
  }

  static Future<void> _saveAll(Map<int, CloudMemoryMetadata> data) async {
    _cache = Map<int, CloudMemoryMetadata>.of(data);
    final prefs = await SharedPreferences.getInstance();
    final json = <String, dynamic>{};
    for (final entry in data.entries) {
      json[entry.key.toString()] = entry.value.toJson();
    }
    await prefs.setString(_key, jsonEncode(json));
  }

  /// Returns all cloud metadata, keyed by memory ID.
  static Future<Map<int, CloudMemoryMetadata>> getAll() async {
    _cache ??= await _loadAll();
    return Map<int, CloudMemoryMetadata>.of(_cache!);
  }

  /// Returns metadata for a single memory, or null.
  static Future<CloudMemoryMetadata?> get(int memoryId) async {
    final all = await getAll();
    return all[memoryId];
  }

  /// Saves (inserts or overwrites) metadata for the given memory.
  static Future<void> save(int memoryId, CloudMemoryMetadata data) async {
    final all = await getAll();
    all[memoryId] = data;
    await _saveAll(all);
  }

  /// Deletes metadata for the given memory. Returns true if it existed.
  static Future<bool> delete(int memoryId) async {
    final all = await getAll();
    final existed = all.containsKey(memoryId);
    if (existed) {
      all.remove(memoryId);
      await _saveAll(all);
    }
    return existed;
  }

  /// Clears all cloud metadata. Use with caution.
  static Future<void> clearAll() async {
    _cache = <int, CloudMemoryMetadata>{};
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Invalidates the in-memory cache so next read reloads from disk.
  static void invalidateCache() {
    _cache = null;
  }
}
