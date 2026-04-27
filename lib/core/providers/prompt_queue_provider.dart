import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_input_data.dart';
import '../models/prompt_queue_item.dart';
import '../services/prompt_queue_service.dart';

class PromptQueueProvider extends ChangeNotifier {
  final PromptQueueService _service = PromptQueueService();
  final Map<String, List<PromptQueueItem>> _queues = {};
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    await _service.init();
    _initialized = true;
  }

  // ==========================================================================
  // Getters
  // ==========================================================================

  List<PromptQueueItem> getQueue(String conversationId) {
    _ensureInitialized();
    return List.unmodifiable(_loadQueueSync(conversationId));
  }

  int getQueueLength(String conversationId) {
    return _loadQueueSync(conversationId).length;
  }

  bool hasItems(String conversationId) {
    return _loadQueueSync(conversationId).isNotEmpty;
  }

  // ==========================================================================
  // Mutators
  // ==========================================================================

  Future<void> enqueue(
    String conversationId,
    PromptQueueItem item,
  ) async {
    _ensureInitialized();
    final queue = _loadQueueSync(conversationId);
    final newItem = item.order >= queue.length
        ? item.copyWith(order: queue.length)
        : item;
    queue.add(newItem);
    _queues[conversationId] = queue;
    await _service.saveQueue(conversationId, queue);
    notifyListeners();
  }

  Future<PromptQueueItem?> popNext(String conversationId) async {
    _ensureInitialized();
    final queue = _loadQueueSync(conversationId);
    if (queue.isEmpty) return null;
    final item = queue.removeAt(0);
    _reindex(queue);
    _queues[conversationId] = queue;
    await _service.saveQueue(conversationId, queue);
    notifyListeners();
    return item;
  }

  Future<void> removeItem(String conversationId, String itemId) async {
    _ensureInitialized();
    final queue = _loadQueueSync(conversationId);
    queue.removeWhere((q) => q.id == itemId);
    _reindex(queue);
    _queues[conversationId] = queue;
    await _service.saveQueue(conversationId, queue);
    notifyListeners();
  }

  Future<void> editItem(
    String conversationId,
    String itemId,
    ChatInputData newInput,
  ) async {
    _ensureInitialized();
    final queue = _loadQueueSync(conversationId);
    final idx = queue.indexWhere((q) => q.id == itemId);
    if (idx < 0) return;
    queue[idx] = queue[idx].copyWith(input: newInput);
    _queues[conversationId] = queue;
    await _service.saveQueue(conversationId, queue);
    notifyListeners();
  }

  Future<void> moveToTop(String conversationId, String itemId) async {
    _ensureInitialized();
    final queue = _loadQueueSync(conversationId);
    final idx = queue.indexWhere((q) => q.id == itemId);
    if (idx <= 0) return;
    final item = queue.removeAt(idx);
    queue.insert(0, item);
    _reindex(queue);
    _queues[conversationId] = queue;
    await _service.saveQueue(conversationId, queue);
    notifyListeners();
  }

  Future<void> moveUp(String conversationId, String itemId) async {
    _ensureInitialized();
    final queue = _loadQueueSync(conversationId);
    final idx = queue.indexWhere((q) => q.id == itemId);
    if (idx <= 0) return;
    final item = queue.removeAt(idx);
    queue.insert(idx - 1, item);
    _reindex(queue);
    _queues[conversationId] = queue;
    await _service.saveQueue(conversationId, queue);
    notifyListeners();
  }

  Future<void> moveDown(String conversationId, String itemId) async {
    _ensureInitialized();
    final queue = _loadQueueSync(conversationId);
    final idx = queue.indexWhere((q) => q.id == itemId);
    if (idx < 0 || idx >= queue.length - 1) return;
    final item = queue.removeAt(idx);
    queue.insert(idx + 1, item);
    _reindex(queue);
    _queues[conversationId] = queue;
    await _service.saveQueue(conversationId, queue);
    notifyListeners();
  }

  Future<void> moveToBottom(String conversationId, String itemId) async {
    _ensureInitialized();
    final queue = _loadQueueSync(conversationId);
    final idx = queue.indexWhere((q) => q.id == itemId);
    if (idx < 0) return;
    if (idx == queue.length - 1) return;
    final item = queue.removeAt(idx);
    queue.add(item);
    _reindex(queue);
    _queues[conversationId] = queue;
    await _service.saveQueue(conversationId, queue);
    notifyListeners();
  }

  Future<void> clearQueue(String conversationId) async {
    _ensureInitialized();
    _queues.remove(conversationId);
    await _service.clearQueue(conversationId);
    notifyListeners();
  }

  // ==========================================================================
  // Helpers
  // ==========================================================================

  List<PromptQueueItem> _loadQueueSync(String conversationId) {
    if (_queues.containsKey(conversationId)) {
      return _queues[conversationId]!;
    }
    final fromDb = _service.getQueue(conversationId);
    _queues[conversationId] = fromDb;
    return fromDb;
  }

  void _reindex(List<PromptQueueItem> queue) {
    for (int i = 0; i < queue.length; i++) {
      queue[i] = queue[i].copyWith(order: i);
    }
  }

  void _ensureInitialized() {
    if (!_initialized) {
      _initialized = true;
      unawaited(init());
    }
  }
}
