import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_input_data.dart';

/// Provider that manages a multi-item, persistent prompt queue.
///
/// When the LLM is busy generating, user messages can be queued here.
/// When generation completes and auto-process is enabled, the next item
/// is popped and sent automatically.
///
/// Storage: SharedPreferences key 'prompt_queue_v1' (JSON array).
class PromptQueueProvider extends ChangeNotifier {
  List<QueuedPrompt> _queue = [];
  bool _isAutoProcess = true;

  // ============================================================================
  // Getters
  // ============================================================================

  List<QueuedPrompt> get queue => List.unmodifiable(_queue);
  int get queueLength => _queue.length;
  bool get hasItems => _queue.isNotEmpty;
  bool get isAutoProcess => _isAutoProcess;

  /// The first item in the queue, or null if empty.
  QueuedPrompt? get nextPrompt => _queue.isNotEmpty ? _queue.first : null;

  // ============================================================================
  // Initialization
  // ============================================================================

  Future<void> initialize() async {
    await _loadQueue();
  }

  // ============================================================================
  // Mutators
  // ============================================================================

  /// Add a new prompt to the end of the queue.
  Future<QueuedPrompt> addToQueue(
    ChatInputData input, {
    required String conversationId,
    String? assistantId,
  }) async {
    final prompt = QueuedPrompt(
      id: const Uuid().v4(),
      conversationId: conversationId,
      input: input,
      position: _queue.length,
      createdAt: DateTime.now(),
      assistantId: assistantId,
    );
    _queue.add(prompt);
    await _saveQueue();
    return prompt;
  }

  /// Remove a prompt by its ID.
  Future<void> removeFromQueue(String id) async {
    _queue.removeWhere((q) => q.id == id);
    _reindex();
    await _saveQueue();
  }

  /// Edit the text of a queued prompt.
  Future<void> editInQueue(String id, String newText) async {
    final index = _queue.indexWhere((q) => q.id == id);
    if (index < 0) return;
    _queue[index] = _queue[index].copyWith(
      input: ChatInputData(
        text: newText,
        imagePaths: _queue[index].input.imagePaths,
        documents: _queue[index].input.documents,
      ),
    );
    await _saveQueue();
  }

  /// Reorder the queue (drag-and-drop).
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _queue.length ||
        newIndex < 0 ||
        newIndex >= _queue.length) {
      return;
    }
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    _reindex();
    await _saveQueue();
  }

  /// Clear all items from the queue.
  Future<void> clearQueue() async {
    _queue.clear();
    await _saveQueue();
  }

  /// Toggle auto-process on/off.
  Future<void> toggleAutoProcess(bool value) async {
    if (_isAutoProcess == value) return;
    _isAutoProcess = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('prompt_queue_auto_process_v1', _isAutoProcess);
  }

  /// Pop and return the first item in the queue, removing it.
  /// Returns null if queue is empty.
  QueuedPrompt? popNext() {
    if (_queue.isEmpty) return null;
    final item = _queue.removeAt(0);
    _reindex();
    // Fire-and-forget save
    unawaited(_saveQueue());
    return item;
  }

  // ============================================================================
  // Persistence
  // ============================================================================

  Future<void> _loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('prompt_queue_v1');
    if (str != null && str.isNotEmpty) {
      try {
        final list = jsonDecode(str) as List;
        _queue = list
            .map((e) => QueuedPrompt.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _queue = [];
      }
    } else {
      _queue = [];
    }
    // Load auto-process setting
    _isAutoProcess = prefs.getBool('prompt_queue_auto_process_v1') ?? true;
    notifyListeners();
  }

  Future<void> _saveQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final json =
        jsonEncode(_queue.map((q) => q.toJson()).toList());
    await prefs.setString('prompt_queue_v1', json);
    notifyListeners();
  }

  void _reindex() {
    for (int i = 0; i < _queue.length; i++) {
      _queue[i] = _queue[i].copyWith(position: i);
    }
  }
}
