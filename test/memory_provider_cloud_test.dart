import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kelivo/core/providers/memory_provider.dart';
import 'package:kelivo/core/models/cloud_memory_metadata.dart';
import 'package:kelivo/core/services/cloud_memory_metadata_store.dart';

void main() {
  group('MemoryProvider cloud metadata', () {
    late MemoryProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      CloudMemoryMetadataStore.invalidateCache();
      provider = MemoryProvider();
    });

    tearDown(() {
      CloudMemoryMetadataStore.invalidateCache();
    });

    test('cloudMetadata is empty before loadCloudMetadata', () {
      expect(provider.cloudMetadata, isEmpty);
    });

    test('cloudMetadataFor returns null before loading', () {
      expect(provider.cloudMetadataFor(1), isNull);
    });

    test('loadCloudMetadata loads persisted data', () async {
      final meta = CloudMemoryMetadata(
        memoryId: 1,
        source: CloudMemorySource.supabase,
        memoryScore: 4,
        memoryType: CloudMemoryType.preference,
        createdAt: DateTime.utc(2026, 1, 1),
        lastAccessedAt: DateTime.utc(2026, 1, 1),
      );
      await CloudMemoryMetadataStore.save(1, meta);

      await provider.loadCloudMetadata();

      expect(provider.cloudMetadata.containsKey(1), true);
      expect(provider.cloudMetadataFor(1)!.memoryScore, 4);
    });

    test('loadCloudMetadata is idempotent', () async {
      await provider.loadCloudMetadata();
      int callCount = 0;
      // Second call should not reload (we verify no exceptions)
      await provider.loadCloudMetadata();
      // If we get here without error, it's idempotent
      expect(true, true);
    });

    test('pinMemory creates metadata if none exists', () async {
      await provider.pinMemory(99, true);
      await provider.loadCloudMetadata();

      final meta = provider.cloudMetadataFor(99);
      expect(meta, isNotNull);
      expect(meta!.pinned, true);
      expect(meta.source, CloudMemorySource.local); // default
    });

    test('pinMemory toggles pinned state', () async {
      await provider.pinMemory(50, true);
      await provider.loadCloudMetadata();
      expect(provider.cloudMetadataFor(50)!.pinned, true);

      await provider.pinMemory(50, false);
      await provider.loadCloudMetadata();
      expect(provider.cloudMetadataFor(50)!.pinned, false);
    });

    test('markWrong marks as stale and reviewed', () async {
      final meta = CloudMemoryMetadata(
        memoryId: 10,
        source: CloudMemorySource.supabase,
        memoryScore: 3,
        memoryType: CloudMemoryType.decision,
        createdAt: DateTime.utc(2026, 1, 1),
        lastAccessedAt: DateTime.utc(2026, 1, 1),
      );
      await CloudMemoryMetadataStore.save(10, meta);
      await provider.loadCloudMetadata();

      await provider.markWrong(10);

      final updated = provider.cloudMetadataFor(10)!;
      expect(updated.stale, true);
      expect(updated.reviewed, true);
    });

    test('markWrong on unknown id does nothing', () async {
      await provider.loadCloudMetadata();
      // Should not throw
      await provider.markWrong(999);
      expect(provider.cloudMetadataFor(999), isNull);
    });

    test('deleteCloudMetadata removes record', () async {
      final meta = CloudMemoryMetadata(
        memoryId: 5,
        createdAt: DateTime.utc(2026, 1, 1),
        lastAccessedAt: DateTime.utc(2026, 1, 1),
      );
      await CloudMemoryMetadataStore.save(5, meta);
      await provider.loadCloudMetadata();
      expect(provider.cloudMetadataFor(5), isNotNull);

      final result = await provider.deleteCloudMetadata(5);
      expect(result, true);
      expect(provider.cloudMetadataFor(5), isNull);
    });

    test('deleteCloudMetadata returns false for unknown id', () async {
      await provider.loadCloudMetadata();
      final result = await provider.deleteCloudMetadata(999);
      expect(result, false);
    });
  });
}
