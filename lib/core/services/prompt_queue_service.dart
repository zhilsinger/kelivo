import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/prompt_queue_item.dart';

class PromptQueueService {
  static const String _boxName = 'prompt_queue_v2';
  Box<String>? _box;

  bool get isInitialized => _box != null && _box!.isOpen;

  Future<void> init() async {
    if (isInitialized) return;
    _box = await Hive.openBox<String>(_boxName);
  }

  String _key(String conversationId) => 'conv_$conversationId';

  List<PromptQueueItem> getQueue(String conversationId) {
    if (!isInitialized) return [];
    final raw = _box!.get(_key(conversationId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => PromptQueueItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveQueue(
      String conversationId, List<PromptQueueItem> items) async {
    if (!isInitialized) return;
    final json = jsonEncode(items.map((q) => q.toJson()).toList());
    await _box!.put(_key(conversationId), json);
  }

  Future<void> clearQueue(String conversationId) async {
    if (!isInitialized) return;
    await _box!.delete(_key(conversationId));
  }
}
