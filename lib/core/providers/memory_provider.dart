import 'package:flutter/foundation.dart';
import '../models/assistant_memory.dart';
import '../models/cloud_memory_metadata.dart';
import '../services/memory_store.dart';
import '../services/cloud_memory_metadata_store.dart';

class MemoryProvider extends ChangeNotifier {
  List<AssistantMemory> _memories = <AssistantMemory>[];
  bool _initialized = false;

  // Cloud metadata sidecar (Extension-by-Addition Rule — never on model)
  Map<int, CloudMemoryMetadata> _cloudMetadata = <int, CloudMemoryMetadata>{};
  bool _cloudLoaded = false;

  List<AssistantMemory> get memories => List.unmodifiable(_memories);

  List<AssistantMemory> getForAssistant(String assistantId) =>
      _memories.where((m) => m.assistantId == assistantId).toList();

  Map<int, CloudMemoryMetadata> get cloudMetadata =>
      Map.unmodifiable(_cloudMetadata);

  CloudMemoryMetadata? cloudMetadataFor(int memoryId) =>
      _cloudMetadata[memoryId];

  Future<void> initialize() async {
    if (_initialized) return;
    await loadAll();
    _initialized = true;
  }

  Future<void> loadAll() async {
    try {
      _memories = await MemoryStore.getAll();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load memories: $e');
      _memories = <AssistantMemory>[];
      notifyListeners();
    }
  }

  Future<AssistantMemory> add({
    required String assistantId,
    required String content,
  }) async {
    final mem = await MemoryStore.add(
      assistantId: assistantId,
      content: content,
    );
    await loadAll();
    return mem;
  }

  Future<AssistantMemory?> update({
    required int id,
    required String content,
  }) async {
    final mem = await MemoryStore.update(id: id, content: content);
    await loadAll();
    return mem;
  }

  Future<bool> delete({required int id}) async {
    final ok = await MemoryStore.delete(id: id);
    await loadAll();
    return ok;
  }

  // ──────────────────────────────────────────────
  // Cloud memory metadata (sidecar store)
  // ──────────────────────────────────────────────

  Future<void> loadCloudMetadata() async {
    if (_cloudLoaded) return;
    try {
      _cloudMetadata = await CloudMemoryMetadataStore.getAll();
      _cloudLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load cloud memory metadata: $e');
    }
  }

  Future<void> pinMemory(int memoryId, bool pinned) async {
    final existing = _cloudMetadata[memoryId];
    final meta = (existing ??
            CloudMemoryMetadata(
              memoryId: memoryId,
              source: CloudMemorySource.local,
              memoryScore: 0,
              memoryType: CloudMemoryType.preference,
              createdAt: DateTime.now(),
              lastAccessedAt: DateTime.now(),
            ))
        .copyWith(pinned: pinned, lastAccessedAt: DateTime.now());
    await CloudMemoryMetadataStore.save(memoryId, meta);
    _cloudMetadata[memoryId] = meta;
    notifyListeners();
  }

  Future<void> markWrong(int memoryId) async {
    final existing = _cloudMetadata[memoryId];
    if (existing == null) return;
    final meta = existing.copyWith(
      stale: true,
      reviewed: true,
      lastAccessedAt: DateTime.now(),
    );
    await CloudMemoryMetadataStore.save(memoryId, meta);
    _cloudMetadata[memoryId] = meta;
    notifyListeners();
  }

  Future<bool> deleteCloudMetadata(int memoryId) async {
    final ok = await CloudMemoryMetadataStore.delete(memoryId);
    if (ok) {
      _cloudMetadata.remove(memoryId);
      notifyListeners();
    }
    return ok;
  }
}
