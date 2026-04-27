import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kelivo/core/models/cloud_memory_metadata.dart';
import 'package:kelivo/core/services/cloud_memory_metadata_store.dart';

void main() {
  group('CloudMemoryMetadataStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() {
      CloudMemoryMetadataStore.invalidateCache();
    });

    test('getAll returns empty map on first access', () async {
      final all = await CloudMemoryMetadataStore.getAll();
      expect(all, isEmpty);
    });

    test('save and retrieve a single record', () async {
      final meta = CloudMemoryMetadata(
        memoryId: 42,
        source: CloudMemorySource.supabase,
        memoryScore: 4,
        memoryType: CloudMemoryType.preference,
        pinned: true,
        createdAt: DateTime.utc(2026, 1, 1),
        lastAccessedAt: DateTime.utc(2026, 1, 2),
      );

      await CloudMemoryMetadataStore.save(42, meta);

      final retrieved = await CloudMemoryMetadataStore.get(42);
      expect(retrieved, isNotNull);
      expect(retrieved!.memoryId, 42);
      expect(retrieved.source, CloudMemorySource.supabase);
      expect(retrieved.memoryScore, 4);
      expect(retrieved.pinned, true);
    });

    test('get returns null for unknown id', () async {
      final result = await CloudMemoryMetadataStore.get(999);
      expect(result, isNull);
    });

    test('save overwrites existing record', () async {
      final meta1 = CloudMemoryMetadata(
        memoryId: 1,
        memoryScore: 2,
        createdAt: DateTime.utc(2026, 1, 1),
        lastAccessedAt: DateTime.utc(2026, 1, 1),
      );
      await CloudMemoryMetadataStore.save(1, meta1);

      final meta2 = meta1.copyWith(memoryScore: 5, pinned: true);
      await CloudMemoryMetadataStore.save(1, meta2);

      final retrieved = await CloudMemoryMetadataStore.get(1);
      expect(retrieved!.memoryScore, 5);
      expect(retrieved.pinned, true);
    });

    test('delete removes record and returns true', () async {
      final meta = CloudMemoryMetadata(
        memoryId: 7,
        createdAt: DateTime.utc(2026, 1, 1),
        lastAccessedAt: DateTime.utc(2026, 1, 1),
      );
      await CloudMemoryMetadataStore.save(7, meta);

      final existed = await CloudMemoryMetadataStore.delete(7);
      expect(existed, true);

      final after = await CloudMemoryMetadataStore.get(7);
      expect(after, isNull);
    });

    test('delete on unknown id returns false', () async {
      final existed = await CloudMemoryMetadataStore.delete(999);
      expect(existed, false);
    });

    test('getAll returns all saved records', () async {
      final meta1 = CloudMemoryMetadata(
        memoryId: 1,
        createdAt: DateTime.utc(2026, 1, 1),
        lastAccessedAt: DateTime.utc(2026, 1, 1),
      );
      final meta2 = CloudMemoryMetadata(
        memoryId: 2,
        createdAt: DateTime.utc(2026, 1, 2),
        lastAccessedAt: DateTime.utc(2026, 1, 2),
      );

      await CloudMemoryMetadataStore.save(1, meta1);
      await CloudMemoryMetadataStore.save(2, meta2);

      final all = await CloudMemoryMetadataStore.getAll();
      expect(all.length, 2);
      expect(all[1]!.memoryId, 1);
      expect(all[2]!.memoryId, 2);
    });

    test('clearAll removes everything', () async {
      final meta = CloudMemoryMetadata(
        memoryId: 1,
        createdAt: DateTime.utc(2026, 1, 1),
        lastAccessedAt: DateTime.utc(2026, 1, 1),
      );
      await CloudMemoryMetadataStore.save(1, meta);

      await CloudMemoryMetadataStore.clearAll();

      final all = await CloudMemoryMetadataStore.getAll();
      expect(all, isEmpty);
    });

    test('fromJson round-trips all fields', () {
      final original = CloudMemoryMetadata(
        memoryId: 42,
        source: CloudMemorySource.supabase,
        sourceThreadId: 'thread-abc',
        sourceMessageId: 'msg-xyz',
        memoryScore: 4,
        memoryType: CloudMemoryType.decision,
        pinned: true,
        reviewed: true,
        createdAt: DateTime.utc(2026, 4, 27, 1, 44),
        lastAccessedAt: DateTime.utc(2026, 4, 27, 2, 0),
        accessCount: 7,
        decayAfterDays: 30,
        stale: false,
      );

      final json = original.toJson();
      final restored = CloudMemoryMetadata.fromJson(json);

      expect(restored.memoryId, original.memoryId);
      expect(restored.source, original.source);
      expect(restored.sourceThreadId, original.sourceThreadId);
      expect(restored.sourceMessageId, original.sourceMessageId);
      expect(restored.memoryScore, original.memoryScore);
      expect(restored.memoryType, original.memoryType);
      expect(restored.pinned, original.pinned);
      expect(restored.reviewed, original.reviewed);
      expect(restored.accessCount, original.accessCount);
      expect(restored.decayAfterDays, original.decayAfterDays);
      expect(restored.stale, original.stale);
    });

    test('copyWith preserves unchanged fields', () {
      final meta = CloudMemoryMetadata(
        memoryId: 1,
        source: CloudMemorySource.local,
        memoryScore: 3,
        memoryType: CloudMemoryType.todo,
        createdAt: DateTime.utc(2026, 1, 1),
        lastAccessedAt: DateTime.utc(2026, 1, 1),
      );

      final updated = meta.copyWith(pinned: true, memoryScore: 5);

      expect(updated.memoryId, 1);
      expect(updated.pinned, true);
      expect(updated.memoryScore, 5);
      expect(updated.source, CloudMemorySource.local);
      expect(updated.memoryType, CloudMemoryType.todo);
    });

    test('corrupt JSON returns empty map gracefully', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cloud_memory_metadata_v1', 'this is not json');
      CloudMemoryMetadataStore.invalidateCache();

      final all = await CloudMemoryMetadataStore.getAll();
      expect(all, isEmpty);
    });
  });
}
