import 'dart:async';
import 'package:dio/dio.dart';

/// Thin wrapper around Supabase REST API using Dio.
/// We avoid the full supabase_flutter dependency by calling the REST API directly,
/// which is sufficient for our use case (upsert threads/messages).
class SupabaseClientService {
  SupabaseClientService._();
  static final SupabaseClientService instance = SupabaseClientService._();

  String? _url;
  String? _anonKey;
  Dio? _dio;

  bool get isConfigured => _url != null && _anonKey != null && _url!.isNotEmpty && _anonKey!.isNotEmpty;
  String? get configuredUrl => _url;

  void configure(String url, String anonKey) {
    _url = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    _anonKey = anonKey;
    _dio = Dio(BaseOptions(
      baseUrl: '$_url/rest/v1',
      headers: {
        'apikey': _anonKey,
        'Authorization': 'Bearer $_anonKey',
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
      },
    ));
  }

  void clear() {
    _url = null;
    _anonKey = null;
    _dio = null;
  }

  Dio get _client {
    if (_dio == null) throw StateError('SupabaseClientService not configured');
    return _dio!;
  }

  /// Test connection by fetching one row from threads
  Future<bool> testConnection() async {
    try {
      await _client.get('/threads', queryParameters: {'select': 'id', 'limit': 1});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Upsert a thread (insert or update by id)
  Future<void> upsertThread(Map<String, dynamic> data) async {
    await _client.post('/threads', data: data, queryParameters: {
      'on_conflict': 'id',
    });
  }

  /// Upsert a message (insert or update by id)
  Future<void> upsertMessage(Map<String, dynamic> data) async {
    await _client.post('/messages', data: data, queryParameters: {
      'on_conflict': 'id',
    });
  }

  /// Upsert multiple messages in batch
  Future<void> upsertMessages(List<Map<String, dynamic>> dataList) async {
    await _client.post('/messages', data: dataList, queryParameters: {
      'on_conflict': 'id',
    });
  }

  /// Delete a thread and its messages (via CASCADE)
  Future<void> deleteThread(String threadId) async {
    await _client.delete('/threads', queryParameters: {
      'id': 'eq.$threadId',
    });
  }

  /// Fetch all threads belonging to this user
  Future<List<Map<String, dynamic>>> fetchThreads() async {
    final response = await _client.get('/threads');
    return (response.data as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  /// Fetch messages for a specific thread
  Future<List<Map<String, dynamic>>> fetchMessages(String threadId) async {
    final response = await _client.get('/messages', queryParameters: {
      'thread_id': 'eq.$threadId',
      'order': 'created_at.asc',
    });
    return (response.data as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  /// Sync a full thread (thread + all messages) to Supabase
  Future<void> syncThread({
    required String id,
    required String title,
    required String source,
    required DateTime createdAt,
    required DateTime updatedAt,
    required List<Map<String, dynamic>> messages,
  }) async {
    await upsertThread({
      'id': id,
      'title': title,
      'source': source,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'synced_at': DateTime.now().toUtc().toIso8601String(),
    });

    if (messages.isNotEmpty) {
      await upsertMessages(messages);
    }
  }

  // ──────────────────────────────────────────────
  // Memory decisions & feedback (Phase 5)
  // ──────────────────────────────────────────────

  /// Fetch memory decisions, optionally filtered by assistant.
  Future<List<Map<String, dynamic>>> fetchMemoryDecisions({String? assistantId}) async {
    final params = <String, String>{
      'select': '*',
      'order': 'created_at.desc',
    };
    if (assistantId != null) {
      params['assistant_id'] = 'eq.$assistantId';
    }
    final response = await _client.get('/memory_decisions', queryParameters: params);
    return (response.data as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  /// Upsert a memory decision (insert or update by id).
  Future<void> upsertMemoryDecision(Map<String, dynamic> data) async {
    await _client.post('/memory_decisions', data: data, queryParameters: {
      'on_conflict': 'id',
    });
  }

  /// Delete a memory decision by its primary key.
  Future<void> deleteMemoryDecision(int id) async {
    await _client.delete('/memory_decisions', queryParameters: {
      'id': 'eq.$id',
    });
  }

  /// Submit user feedback on a memory retrieval.
  Future<void> submitMemoryFeedback(Map<String, dynamic> data) async {
    await _client.post('/memory_feedback', data: data);
  }
}
