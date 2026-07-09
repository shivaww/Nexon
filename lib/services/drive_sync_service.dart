import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GoogleAuthClient extends http.BaseClient {
  GoogleAuthClient(this._token);

  final String _token;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

class DriveSyncResult {
  const DriveSyncResult({
    required this.success,
    required this.message,
    this.needsRelogin = false,
  });

  final bool success;
  final String message;
  final bool needsRelogin;
}

class DriveSyncService {
  static final _secureStorage = const FlutterSecureStorage();
  static const _backupFileName = 'nexon_backup.json';
  static const _tokenKey = 'google_provider_token';
  static const _refreshTokenKey = 'google_provider_refresh_token';
  static const _maxArtifactBytes = 2 * 1024 * 1024;
  static const _textExtensions = {
    '.md',
    '.svg',
    '.json',
    '.txt',
    '.html',
    '.css',
    '.js',
    '.ts',
    '.dart',
    '.py',
    '.yaml',
    '.yml',
    '.xml',
    '.csv',
    '.log',
  };

  static Future<bool> syncToDrive(
    List<dynamic> sessions, {
    bool force = false,
  }) async {
    final result = await syncToDriveDetailed(sessions, force: force);
    return result.success;
  }

  static Future<bool> restoreFromDrive() async {
    final result = await restoreFromDriveDetailed();
    return result.success;
  }

  static Future<DriveSyncResult> syncToDriveDetailed(
    List<dynamic> sessions, {
    bool force = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final backupEnabled = prefs.getBool('google_drive_backup_enabled') ?? false;
    if (!backupEnabled && !force) {
      return const DriveSyncResult(
        success: false,
        message: 'Google Drive backup is disabled.',
      );
    }

    return _withDriveApi((driveApi) async {
      final backupData = await _buildBackupPayload(sessions, prefs);
      final jsonBackup = jsonEncode(backupData);
      final bytes = utf8.encode(jsonBackup);
      final media = drive.Media(Stream.value(bytes), bytes.length);

      final existing = await _findBackupFile(driveApi);
      if (existing?.id != null) {
        await driveApi.files.update(
          drive.File()
            ..name = _backupFileName
            ..modifiedTime = DateTime.now().toUtc(),
          existing!.id!,
          uploadMedia: media,
        );
      } else {
        await driveApi.files.create(
          drive.File()
            ..name = _backupFileName
            ..parents = ['appDataFolder'],
          uploadMedia: media,
        );
      }

      return DriveSyncResult(
        success: true,
        message:
            'Backed up ${sessions.length} chat session(s), ${backupData['artifact_count']} artifact(s), ${backupData['provider_api_key_count']} provider key(s), settings, memory, and metadata.',
      );
    });
  }

  static Future<DriveSyncResult> restoreFromDriveDetailed() async {
    final prefs = await SharedPreferences.getInstance();

    return _withDriveApi((driveApi) async {
      final existing = await _findBackupFile(driveApi);
      if (existing?.id == null) {
        return const DriveSyncResult(
          success: false,
          message: 'No Google Drive backup found for this app.',
        );
      }

      final response =
          await driveApi.files.get(
                existing!.id!,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;

      final bytes = <int>[];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
      }
      final backupData = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

      await _restorePrefsString(
        prefs,
        backupData,
        'chat_sessions',
        'chat_sessions_v1',
      );
      await _restorePrefsString(
        prefs,
        backupData,
        'provider_settings',
        'provider_settings_v1',
      );
      await _restoreProviderApiKeys(prefs, backupData['provider_api_keys']);
      await _restorePrefsString(
        prefs,
        backupData,
        'active_session_id',
        'active_session_id_v1',
      );
      await _restorePrefsString(
        prefs,
        backupData,
        'selected_provider_id',
        'selected_provider_id',
      );
      if (!backupData.containsKey('selected_provider_id')) {
        await _restorePrefsString(
          prefs,
          backupData,
          'selected_provider',
          'selected_provider_id',
        );
      }
      await _restorePrefsString(
        prefs,
        backupData,
        'search_settings',
        'search_settings_v1',
      );
      await _restorePrefsBool(
        prefs,
        backupData,
        'agentic_enabled',
        'agentic_enabled_v1',
      );
      await _restorePrefsString(
        prefs,
        backupData,
        'agentic_workspace',
        'agentic_workspace_v1',
      );
      await _restorePrefsString(
        prefs,
        backupData,
        'shell_permission',
        'shell_permission_v1',
      );
      await _restorePrefsString(
        prefs,
        backupData,
        'custom_mcp_url',
        'custom_mcp_url_v1',
      );

      final docDir = await getApplicationDocumentsDirectory();
      final aiMemory = backupData['ai_memory'];
      if (aiMemory != null) {
        await File(
          '${docDir.path}/nexon_memory.json',
        ).writeAsString(aiMemory.toString());
      }
      await _restoreArtifacts(docDir, backupData['artifacts']);

      return const DriveSyncResult(
        success: true,
        message:
            'Restore complete. Chats, provider keys, settings, memory, and artifacts were restored.',
      );
    });
  }

  static Future<DriveSyncResult> _withDriveApi(
    Future<DriveSyncResult> Function(drive.DriveApi driveApi) action,
  ) async {
    GoogleAuthClient? client;
    try {
      final token = await _getFreshGoogleProviderToken();
      if (token == null || token.isEmpty) {
        return const DriveSyncResult(
          success: false,
          needsRelogin: true,
          message:
              'Google Drive token is missing. Sign out and sign in with Google Drive access again.',
        );
      }
      client = GoogleAuthClient(token);
      return await action(drive.DriveApi(client));
    } catch (e) {
      final errorText = e.toString();
      final needsRelogin =
          errorText.contains('401') ||
          errorText.contains('403') ||
          errorText.toLowerCase().contains('unauthorized') ||
          errorText.toLowerCase().contains('insufficient');
      return DriveSyncResult(
        success: false,
        needsRelogin: needsRelogin,
        message: needsRelogin
            ? 'Google Drive permission expired or missing. Sign in with Google again and allow Drive access.'
            : 'Google Drive backup error: $e',
      );
    } finally {
      client?.close();
    }
  }

  static Future<String?> _getFreshGoogleProviderToken() async {
    final prefs = await SharedPreferences.getInstance();
    final auth = Supabase.instance.client.auth;

    var session = auth.currentSession;
    if (session == null) return prefs.getString(_tokenKey);

    final currentToken = session.providerToken;
    if (currentToken != null && currentToken.isNotEmpty) {
      await prefs.setString(_tokenKey, currentToken);
      final refreshToken = session.providerRefreshToken;
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await prefs.setString(_refreshTokenKey, refreshToken);
      }
      return currentToken;
    }

    try {
      final refreshed = await auth.refreshSession();
      session = refreshed.session ?? auth.currentSession ?? session;
    } catch (_) {
      session = auth.currentSession ?? session;
    }

    final token = session.providerToken;
    if (token != null && token.isNotEmpty) {
      await prefs.setString(_tokenKey, token);
      final refreshToken = session.providerRefreshToken;
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await prefs.setString(_refreshTokenKey, refreshToken);
      }
      return token;
    }
    return prefs.getString(_tokenKey);
  }

  static Future<drive.File?> _findBackupFile(drive.DriveApi driveApi) async {
    final files = await driveApi.files.list(
      spaces: 'appDataFolder',
      q: "name = '$_backupFileName' and trashed = false",
      $fields: 'files(id,name,modifiedTime,size)',
      pageSize: 1,
    );
    return files.files?.isNotEmpty == true ? files.files!.first : null;
  }

  static Future<Map<String, dynamic>> _buildBackupPayload(
    List<dynamic> sessions,
    SharedPreferences prefs,
  ) async {
    final docDir = await getApplicationDocumentsDirectory();
    final serializedSessions = sessions.map((s) {
      if (s is Map) return s;
      try {
        return (s as dynamic).toJson();
      } catch (_) {
        return s;
      }
    }).toList();

    final artifacts = await _collectArtifacts(docDir);
    final memoryFile = File('${docDir.path}/nexon_memory.json');
    final providerApiKeys = await _collectProviderApiKeys(prefs);

    return {
      'version': 2,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'chat_sessions': serializedSessions,
      'active_session_id': prefs.getString('active_session_id_v1') ?? '',
      'provider_settings': prefs.getString('provider_settings_v1') ?? '{}',
      'provider_api_keys': providerApiKeys,
      'provider_api_key_count': providerApiKeys.length,
      'selected_provider_id': prefs.getString('selected_provider_id') ?? '',
      'search_settings': prefs.getString('search_settings_v1') ?? '{}',
      'agentic_enabled': prefs.getBool('agentic_enabled_v1') ?? true,
      'agentic_workspace': prefs.getString('agentic_workspace_v1') ?? '',
      'shell_permission': prefs.getString('shell_permission_v1') ?? 'ask',
      'custom_mcp_url': prefs.getString('custom_mcp_url_v1') ?? '',
      'ai_memory': await memoryFile.exists()
          ? await memoryFile.readAsString()
          : '',
      'artifacts': artifacts,
      'artifact_count': artifacts.length,
    };
  }

  static Future<Map<String, String>> _collectProviderApiKeys(
    SharedPreferences prefs,
  ) async {
    final providerIds = <String>{};
    final rawSettings = prefs.getString('provider_settings_v1');
    if (rawSettings != null && rawSettings.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSettings);
        if (decoded is Map) {
          providerIds.addAll(decoded.keys.map((key) => key.toString()));
        }
      } catch (_) {}
    }

    for (final key in prefs.getKeys()) {
      if (key.startsWith('fallback_api_key_')) {
        providerIds.add(key.substring('fallback_api_key_'.length));
      }
    }

    final keys = <String, String>{};
    for (final providerId in providerIds) {
      final storageKey = _providerApiKeyStorageName(providerId);
      String? value;
      try {
        value = await _secureStorage.read(key: storageKey);
      } catch (_) {
        value = prefs.getString('fallback_api_key_$providerId');
      }
      value ??= prefs.getString('fallback_api_key_$providerId');
      if (value != null && value.trim().isNotEmpty) {
        keys[providerId] = value;
      }
    }
    return keys;
  }

  static Future<Map<String, dynamic>> _collectArtifacts(
    Directory docDir,
  ) async {
    final roots = [
      Directory('${docDir.path}/brain'),
      Directory('${docDir.path}/artifacts'),
    ];
    final out = <String, dynamic>{};

    for (final root in roots) {
      if (!await root.exists()) continue;
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        try {
          final size = await entity.length();
          if (size > _maxArtifactBytes) continue;

          final relPath = _relativePath(entity.path, root.path);
          final ext = _extension(entity.path).toLowerCase();
          final isText = _textExtensions.contains(ext);
          out['${_basename(root.path)}/$relPath'] = {
            'encoding': isText ? 'text' : 'base64',
            'content': isText
                ? await entity.readAsString()
                : base64Encode(await entity.readAsBytes()),
          };
        } catch (_) {
          continue;
        }
      }
    }
    return out;
  }

  static Future<void> _restoreArtifacts(
    Directory docDir,
    Object? artifactsData,
  ) async {
    if (artifactsData == null) return;
    final Map<String, dynamic> raw;
    try {
      if (artifactsData is String) {
        if (artifactsData.trim().isEmpty) return;
        final decoded = jsonDecode(artifactsData);
        if (decoded is! Map) return;
        raw = Map<String, dynamic>.from(decoded);
      } else if (artifactsData is Map) {
        raw = Map<String, dynamic>.from(artifactsData);
      } else {
        return;
      }
    } catch (_) {
      return;
    }

    for (final entry in raw.entries) {
      final safeRel = _safeRelativePath(entry.key);
      if (safeRel == null) continue;
      final targetRel = safeRel.contains('/') ? safeRel : 'brain/$safeRel';
      final file = File('${docDir.path}/$targetRel');
      await file.parent.create(recursive: true);

      final value = entry.value;
      if (value is Map) {
        final encoding = value['encoding']?.toString() ?? 'text';
        final content = value['content']?.toString() ?? '';
        if (encoding == 'base64') {
          await file.writeAsBytes(base64Decode(content));
        } else {
          await file.writeAsString(content);
        }
      } else {
        await file.writeAsString(value.toString());
      }
    }
  }

  static Future<void> _restorePrefsString(
    SharedPreferences prefs,
    Map<String, dynamic> data,
    String backupKey,
    String prefsKey,
  ) async {
    if (!data.containsKey(backupKey)) return;
    final value = data[backupKey];
    await prefs.setString(
      prefsKey,
      value is String ? value : jsonEncode(value),
    );
  }

  static Future<void> _restorePrefsBool(
    SharedPreferences prefs,
    Map<String, dynamic> data,
    String backupKey,
    String prefsKey,
  ) async {
    if (data[backupKey] is bool) {
      await prefs.setBool(prefsKey, data[backupKey] as bool);
    }
  }

  static Future<void> _restoreProviderApiKeys(
    SharedPreferences prefs,
    Object? apiKeysData,
  ) async {
    if (apiKeysData == null) return;

    final Map<String, dynamic> apiKeys;
    try {
      if (apiKeysData is String) {
        if (apiKeysData.trim().isEmpty) return;
        final decoded = jsonDecode(apiKeysData);
        if (decoded is! Map) return;
        apiKeys = Map<String, dynamic>.from(decoded);
      } else if (apiKeysData is Map) {
        apiKeys = Map<String, dynamic>.from(apiKeysData);
      } else {
        return;
      }
    } catch (_) {
      return;
    }

    for (final entry in apiKeys.entries) {
      final providerId = entry.key;
      if (providerId.trim().isEmpty || providerId.contains('/')) continue;
      final apiKey = entry.value?.toString() ?? '';
      if (apiKey.trim().isEmpty) continue;

      try {
        await _secureStorage.write(
          key: _providerApiKeyStorageName(providerId),
          value: apiKey,
        );
        await prefs.remove('fallback_api_key_$providerId');
      } catch (_) {
        await prefs.setString('fallback_api_key_$providerId', apiKey);
      }
    }
  }

  static String _relativePath(String path, String from) {
    final normalizedPath = path.replaceAll('\\', '/');
    final normalizedFrom = from.replaceAll('\\', '/');
    if (normalizedPath.startsWith('$normalizedFrom/')) {
      return normalizedPath.substring(normalizedFrom.length + 1);
    }
    return _basename(normalizedPath);
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((part) => part.isNotEmpty);
    return parts.isEmpty ? normalized : parts.last;
  }

  static String _extension(String path) {
    final name = _basename(path);
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot);
  }

  static String _providerApiKeyStorageName(String providerId) =>
      'provider_api_key_$providerId';

  static String? _safeRelativePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.startsWith('/')) return null;
    final parts = <String>[];
    for (final part in normalized.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') return null;
      parts.add(part);
    }
    return parts.isEmpty ? null : parts.join('/');
  }
}
