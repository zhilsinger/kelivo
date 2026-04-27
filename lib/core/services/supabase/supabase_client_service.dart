import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Result of a table validation check.
class TableValidationResult {
  final bool exists;
  final String? error;
  const TableValidationResult({required this.exists, this.error});
}

/// Comprehensive Supabase client wrapping REST API + Storage via Dio.
///
/// Covers:
/// - Postgres tables (REST via PostgREST)
/// - Storage buckets (REST via Storage API)
/// - RPC functions (for pgvector/hybrid search)
/// - Auth (anon sign-in for RLS user identity)
class SupabaseClientService {
  SupabaseClientService._();
  static final SupabaseClientService instance = SupabaseClientService._();

  String? _url;
  String? _anonKey;
  String? _userId;
  Dio? _dio;
  Dio? _storageDio;

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------
  bool get isConfigured =>
      _url != null &&
      _anonKey != null &&
      _url!.isNotEmpty &&
      _anonKey!.isNotEmpty;
  String? get configuredUrl => _url;
  String? get userId => _userId;

  void configure(String url, String anonKey, {String? userId}) {
    _url = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    _anonKey = anonKey;
    _userId = userId;

    final baseHeaders = <String, String>{
      'apikey': _anonKey!,
      'Authorization': 'Bearer $_anonKey',
      'Content-Type': 'application/json',
      'Prefer': 'return=minimal',
    };
    if (_userId != null && _userId!.isNotEmpty) {
      baseHeaders['x-user-id'] = _userId!;
    }

    _dio = Dio(BaseOptions(
      baseUrl: '$_url/rest/v1',
      headers: baseHeaders,
    ));

    _storageDio = Dio(BaseOptions(
      baseUrl: '$_url/storage/v1',
      headers: {
        'apikey': _anonKey!,
        'Authorization': 'Bearer $_anonKey',
        'x-user-id': _userId ?? '',
      },
    ));
  }

  void clear() {
    _url = null;
    _anonKey = null;
    _userId = null;
    _dio = null;
    _storageDio = null;
  }

  Dio get _client {
    if (_dio == null) {
      throw StateError('SupabaseClientService not configured');
    }
    return _dio!;
  }

  Dio get _storage {
    if (_storageDio == null) {
      throw StateError('SupabaseClientService storage not configured');
    }
    return _storageDio!;
  }

  // ===========================================================================
  // Connection & Table Validation
  // ===========================================================================

  /// Required tables that must exist for the app to function.
  static const _requiredTables = ['threads', 'messages'];

  /// Test connection by checking that required tables exist and are accessible.
  /// Returns: null = success, otherwise the error string.
  Future<Map<String, TableValidationResult>> validateTables() async {
    final results = <String, TableValidationResult>{};
    for (final table in _requiredTables) {
      try {
        await _client.get('/$table', queryParameters: {
          'select': 'id',
          'limit': 1,
        });
        results[table] = const TableValidationResult(exists: true);
      } catch (e) {
        results[table] = TableValidationResult(
          exists: false,
          error: _readableError(e),
        );
      }
    }
    return results;
  }

  /// Quick test: can we reach the API at all?
  Future<bool> testConnection() async {
    try {
      // Just check if the API responds to a simple request
      await _client.get('/threads', queryParameters: {
        'select': 'id',
        'limit': 1,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  // ===========================================================================
  // Threads
  // ===========================================================================

  Future<void> upsertThread(Map<String, dynamic> data) async {
    await _client.post('/threads', data: data, queryParameters: {
      'on_conflict': 'id',
    });
  }

  Future<List<Map<String, dynamic>>> fetchThreads() async {
    final response = await _client.get('/threads', queryParameters: {
      'order': 'updated_at.desc',
    });
    return (response.data as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<void> deleteThread(String threadId) async {
    await _client.delete('/threads', queryParameters: {
      'id': 'eq.$threadId',
    });
  }

  // ===========================================================================
  // Messages
  // ===========================================================================

  Future<void> upsertMessage(Map<String, dynamic> data) async {
    await _client.post('/messages', data: data, queryParameters: {
      'on_conflict': 'id',
    });
  }

  Future<void> upsertMessages(List<Map<String, dynamic>> dataList) async {
    await _client.post('/messages', data: dataList, queryParameters: {
      'on_conflict': 'id',
    });
  }

  Future<List<Map<String, dynamic>>> fetchMessages(String threadId) async {
    final response = await _client.get('/messages', queryParameters: {
      'thread_id': 'eq.$threadId',
      'order': 'created_at.asc',
    });
    return (response.data as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  // ===========================================================================
  // Sync Manifest (incremental sync tracking)
  // ===========================================================================

  Future<Map<String, dynamic>?> getSyncManifest(
    String entityType,
    String entityId,
  ) async {
    try {
      final response = await _client.get('/sync_manifest', queryParameters: {
        'entity_type': 'eq.$entityType',
        'entity_id': 'eq.$entityId',
        'limit': '1',
      });
      final list = (response.data as List?) ?? [];
      return list.isNotEmpty
          ? (list.first as Map).cast<String, dynamic>()
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> upsertSyncManifest(Map<String, dynamic> data) async {
    await _client.post('/sync_manifest', data: data, queryParameters: {
      'on_conflict': 'entity_type,entity_id',
    });
  }

  Future<List<Map<String, dynamic>>> fetchFailedSyncItems() async {
    final response = await _client.get('/sync_manifest', queryParameters: {
      'sync_status': 'in.(failed,retrying)',
      'order': 'last_synced_at.asc',
    });
    return (response.data as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  // ===========================================================================
  // Backup Manifests
  // ===========================================================================

  Future<void> insertBackupManifest(Map<String, dynamic> data) async {
    await _client.post('/backup_manifests', data: data);
  }

  Future<List<Map<String, dynamic>>> fetchBackupManifests() async {
    final response = await _client.get('/backup_manifests', queryParameters: {
      'order': 'created_at.desc',
    });
    return (response.data as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<void> updateBackupManifest(
    String id,
    Map<String, dynamic> data,
  ) async {
    await _client.patch('/backup_manifests', data: data, queryParameters: {
      'id': 'eq.$id',
    });
  }

  Future<void> deleteBackupManifest(String id) async {
    await _client.delete('/backup_manifests', queryParameters: {
      'id': 'eq.$id',
    });
  }

  // ===========================================================================
  // Storage (Supabase Storage buckets)
  // ===========================================================================

  /// Upload a file to a Supabase Storage bucket.
  /// [bucket] = bucket name, [path] = object path within bucket.
  Future<void> uploadFile({
    required String bucket,
    required String path,
    required File file,
    String? contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final fileBytes = await file.readAsBytes();
    final formData = FormData.fromMap({
      '': MultipartFile.fromBytes(fileBytes, filename: path.split('/').last),
    });

    await _storage.post(
      '/object/$bucket/$path',
      data: formData,
      options: Options(
        contentType: contentType ?? 'application/octet-stream',
      ),
      onSendProgress: onProgress,
    );
  }

  /// Download a file from Supabase Storage to a local path.
  Future<void> downloadFile({
    required String bucket,
    required String path,
    required String destinationPath,
  }) async {
    await _storage.download(
      '/object/$bucket/$path',
      destinationPath,
    );
  }

  /// List objects in a storage bucket (optional prefix filter).
  Future<List<Map<String, dynamic>>> listStorageObjects({
    required String bucket,
    String? prefix,
  }) async {
    final response = await _storage.post(
      '/object/list/$bucket',
      data: {
        'prefix': prefix ?? '',
        'limit': 100,
        'offset': 0,
        'sortBy': {'column': 'created_at', 'order': 'desc'},
      },
    );
    return (response.data as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  /// Delete a file from a storage bucket.
  Future<void> deleteStorageFile({
    required String bucket,
    required List<String> paths,
  }) async {
    await _storage.delete(
      '/object/$bucket',
      data: {'prefixes': paths},
    );
  }

  /// Create a public signed URL for a storage object (valid for [expiresIn] seconds).
  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    int expiresIn = 3600,
  }) async {
    final response = await _storage.post(
      '/object/sign/$bucket/$path',
      data: {'expiresIn': expiresIn},
    );
    return (response.data as Map)['signedURL'] as String? ?? '';
  }

  // ===========================================================================
  // RPC (for pgvector hybrid search, future use)
  // ===========================================================================

  /// Call a stored Postgres function via RPC.
  Future<dynamic> rpc(String functionName, {Map<String, dynamic>? params}) async {
    final response = await _client.post(
      '/rpc/$functionName',
      data: params ?? {},
    );
    return response.data;
  }

  // ===========================================================================
  // Edge Functions
  // ===========================================================================

  /// Call a Supabase Edge Function.
  Future<Map<String, dynamic>> invokeEdgeFunction(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    final response = await Dio(BaseOptions(
      baseUrl: '$_url/functions/v1',
      headers: {
        'Authorization': 'Bearer $_anonKey',
        'Content-Type': 'application/json',
        if (_userId != null) 'x-user-id': _userId!,
      },
    )).post('/$functionName', data: body);
    return (response.data as Map).cast<String, dynamic>();
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  /// Compute a stable SHA-256 hash of a string for sync diffing.
  static String hashContent(String content) {
    final bytes = utf8.encode(content);
    return sha256.convert(bytes).toString().substring(0, 32);
  }

  /// Sync a full thread (thread + messages) to Supabase in one call.
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
      'user_id': _userId ?? '',
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'synced_at': DateTime.now().toUtc().toIso8601String(),
    });

    if (messages.isNotEmpty) {
      final withUserId = messages.map((m) => {
        ...m,
        'user_id': _userId ?? '',
        'thread_id': id,
      }).toList();
      await upsertMessages(withUserId);
    }
  }

  static String _readableError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        return 'Permission denied — check Anon Key and RLS policies';
      }
      if (status == 404) {
        return 'Not found — run the SQL migration first';
      }
      return 'HTTP $status: ${e.message}';
    }
    return e.toString();
  }
}
