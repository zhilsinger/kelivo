import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/backup.dart';
import '../services/backup/data_sync.dart';
import '../services/chat/chat_service.dart';
import '../services/supabase/supabase_client_service.dart';

class SupabaseBackupProvider extends ChangeNotifier {
  final DataSync _dataSync;
  final SupabaseClientService _client;

  SupabaseBackupConfig _cfg;
  bool _busy = false;
  String? _message;

  SupabaseBackupProvider({
    required ChatService chatService,
    SupabaseBackupConfig? initialConfig,
  })  : _dataSync = DataSync(chatService: chatService),
        _client = SupabaseClientService.instance,
        _cfg = initialConfig ?? const SupabaseBackupConfig();

  SupabaseBackupConfig get config => _cfg;
  bool get busy => _busy;
  String? get message => _message;

  void updateConfig(SupabaseBackupConfig cfg) {
    _cfg = cfg;
    notifyListeners();
  }

  /// DataSync uses WebDavConfig for include flags; other fields are ignored.
  WebDavConfig _scopeAsWebdavConfig() => WebDavConfig(
    includeChats: _cfg.includeChats,
    includeFiles: _cfg.includeFiles,
  );

  String _effectiveBucket() =>
      _cfg.bucketName.trim().isEmpty ? 'kelivo-backups' : _cfg.bucketName.trim();

  Future<Directory> _ensureTempDir() async {
    Directory dir = await getTemporaryDirectory();
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } catch (_) {}
    }
    if (!await dir.exists()) {
      dir = await Directory.systemTemp.createTemp('kelivo_tmp_');
    }
    return dir;
  }

  Future<void> test() async {
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      if (!_client.isConfigured) {
        throw Exception('Supabase not configured');
      }
      // Validate API access by fetching manifests (simple GET)
      await _client.fetchBackupManifests();
      _message = 'OK';
    } catch (e) {
      _message = e.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> backup() async {
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      if (!_client.isConfigured) {
        throw Exception('Supabase not configured');
      }

      // 1. Create the ZIP backup file via DataSync
      final file = await _dataSync.prepareBackupFile(_scopeAsWebdavConfig());
      final fileName = p.basename(file.path);
      final bucket = _effectiveBucket();
      final path = 'backups/$fileName';

      // 2. Upload to Supabase Storage
      await _client.uploadFile(
        bucket: bucket,
        path: path,
        file: file,
      );

      // 3. Record manifest in Postgres
      final fileSize = await file.length();
      await _client.insertBackupManifest({
        'user_id': _client.userId ?? '',
        'storage_path': path,
        'backup_type': 'full',
        'size_bytes': fileSize,
        'compressed': true,
        'encrypted': false,
        'status': 'completed',
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      });

      _message = 'Backup uploaded';
    } catch (e) {
      _message = e.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<List<BackupFileItem>> listRemote() async {
    if (!_client.isConfigured) return [];
    final bucket = _effectiveBucket();

    // Primary source: backup_manifests table
    try {
      final manifests = await _client.fetchBackupManifests();
      if (manifests.isNotEmpty) {
        return manifests.map((m) {
          final storagePath = (m['storage_path'] as String?) ?? '';
          return BackupFileItem(
            href: Uri.parse('supabase://$bucket/$storagePath'),
            displayName: storagePath.split('/').last,
            size: (m['size_bytes'] as num?)?.toInt() ?? 0,
            lastModified: m['completed_at'] != null
                ? DateTime.tryParse(m['completed_at'] as String)
                : null,
          );
        }).toList();
      }
    } catch (_) {
      // Fall through to storage listing
    }

    // Fallback: list storage objects directly
    try {
      final objects = await _client.listStorageObjects(
        bucket: bucket,
        prefix: 'backups/',
      );
      return objects.map((o) {
        final name = (o['name'] as String?) ?? '';
        final metadata = o['metadata'] as Map<String, dynamic>?;
        return BackupFileItem(
          href: Uri.parse('supabase://$bucket/$name'),
          displayName: name.split('/').last,
          size: (metadata?['size'] as num?)?.toInt() ??
              (o['size'] as num?)?.toInt() ??
              0,
          lastModified: o['created_at'] != null
              ? DateTime.tryParse(o['created_at'] as String)
              : null,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> restoreFromItem(
    BackupFileItem item, {
    RestoreMode mode = RestoreMode.overwrite,
  }) async {
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      if (!_client.isConfigured) {
        throw Exception('Supabase not configured');
      }

      final bucket = _effectiveBucket();
      // Extract path from href (format: supabase://bucket/path)
      final path = item.href.path.startsWith('/')
          ? item.href.path.substring(1)
          : item.href.path;

      final tmp = await _ensureTempDir();
      final file = File(p.join(tmp.path, item.displayName));

      await _client.downloadFile(
        bucket: bucket,
        path: path,
        destinationPath: file.path,
      );

      await _dataSync.restoreFromLocalFile(
        file,
        _scopeAsWebdavConfig(),
        mode: mode,
      );

      try {
        await file.delete();
      } catch (_) {}

      _message = 'Restored';
    } catch (e) {
      _message = e.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<List<BackupFileItem>> deleteAndReload(BackupFileItem item) async {
    final bucket = _effectiveBucket();
    final path = item.href.path.startsWith('/')
        ? item.href.path.substring(1)
        : item.href.path;

    // Delete from storage
    await _client.deleteStorageFile(bucket: bucket, paths: [path]);

    // Delete from manifest table (best effort — find by storage_path)
    try {
      final manifests = await _client.fetchBackupManifests();
      for (final m in manifests) {
        if ((m['storage_path'] as String?) == path) {
          await _client.deleteBackupManifest(m['id'] as String);
          break;
        }
      }
    } catch (_) {}

    return listRemote();
  }
}