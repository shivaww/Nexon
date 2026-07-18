import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// HTTP client that injects a Bearer token into every request.
class GoogleAuthClient extends http.BaseClient {
  GoogleAuthClient(this._token);

  final String _token;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }

  void close() {
    _inner.close();
  }
}

/// Result of a Drive sync operation with detailed info.
class DriveSyncResult {
  const DriveSyncResult({
    required this.success,
    required this.message,
    this.needsRelogin = false,
    this.details = const [],
  });

  final bool success;
  final String message;
  final bool needsRelogin;
  /// Step-by-step log of what happened (for debug display).
  final List<String> details;
}

/// Progress callback signature: receives a human-readable status string.
typedef SyncProgressCallback = void Function(String status);

class DriveSyncService {
  static final _secureStorage = const FlutterSecureStorage();
  static const _backupFileName = 'nexon_backup.json';
  static const _tokenKey = 'google_provider_token';
  static const _refreshTokenKey = 'google_provider_refresh_token';
  static const _tokenExpiryKey = 'google_provider_token_expiry';
  // This is a public OAuth client identifier, not a client secret. It must
  // match the Google OAuth client configured in Supabase for this Android app.
  static const _googleOAuthClientId = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_ID',
  );
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

  /// Image and video file extensions to include in backups as base64.
  static const _mediaExtensions = {
    // Images
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
    '.ico',
    // Videos
    '.mp4',
    '.webm',
    '.mov',
    '.avi',
    '.mkv',
    '.m4v',
    '.3gp',
  };

  // ──────────────────────────────────────────────────────────────────
  // Public: persist the provider token right after a successful OAuth
  // sign-in so that subsequent Drive calls work even after the
  // Supabase session loses the providerToken field.
  // ──────────────────────────────────────────────────────────────────
  /// Call this immediately after a successful Google OAuth sign-in
  /// to persist the provider token and refresh token to secure storage.
  static Future<void> persistProviderToken() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    final token = session.providerToken;
    final refresh = session.providerRefreshToken;
    await _storeGoogleTokens(accessToken: token, refreshToken: refresh);
  }

  // ──────────────────────────────────────────────────────────────────
  // Public convenience wrappers (legacy API, no progress)
  // ──────────────────────────────────────────────────────────────────
  /// Guards against multiple concurrent auto-syncs.
  static bool _isSyncing = false;
  /// Pending debounce data for auto-sync.
  static List<dynamic>? _pendingSessions;
  static Future<void>? _pendingDebounce;

  static Future<bool> syncToDrive(
    List<dynamic> sessions, {
    bool force = false,
  }) async {
    if (force) {
      // Force bypasses debounce
      final result = await syncToDriveDetailed(sessions, force: true);
      return result.success;
    }

    // Debounce auto-sync: store the latest sessions and schedule
    // a single upload 5 seconds from now. If another call arrives
    // before the timer fires, it just updates _pendingSessions.
    _pendingSessions = sessions;
    _pendingDebounce ??= Future.delayed(
      const Duration(seconds: 5),
      () async {
        _pendingDebounce = null;
        final toSync = _pendingSessions;
        _pendingSessions = null;
        if (toSync == null) return;
        if (_isSyncing) return; // another sync already running
        _isSyncing = true;
        try {
          await syncToDriveDetailed(toSync, force: false);
        } finally {
          _isSyncing = false;
        }
      },
    );
    return true; // optimistic — real result is fire-and-forget
  }

  static Future<bool> restoreFromDrive() async {
    final result = await restoreFromDriveDetailed();
    return result.success;
  }

  // ──────────────────────────────────────────────────────────────────
  // BACKUP (upload to Drive)
  // ──────────────────────────────────────────────────────────────────
  static Future<DriveSyncResult> syncToDriveDetailed(
    List<dynamic> sessions, {
    bool force = false,
    SyncProgressCallback? onProgress,
  }) async {
    final log = <String>[];

    // ── Step 0: check if backup is enabled ──
    final prefs = await SharedPreferences.getInstance();
    final backupEnabled = prefs.getBool('google_drive_backup_enabled') ?? false;
    if (!backupEnabled && !force) {
      return const DriveSyncResult(
        success: false,
        message: 'Google Drive backup is disabled in settings.',
      );
    }

    // ── Step 1: get a valid token ──
    onProgress?.call('Authenticating with Google Drive…');
    log.add('⏳ Authenticating…');
    final tokenResult = await _getValidGoogleToken();
    if (tokenResult.error != null) {
      log.add('❌ Auth failed: ${tokenResult.error}');
      return DriveSyncResult(
        success: false,
        needsRelogin: tokenResult.needsRelogin,
        message: tokenResult.error!,
        details: log,
      );
    }
    log.add('✅ Authenticated');

    try {
      // ── Step 2: build backup payload ──
      onProgress?.call('Collecting chats, settings, keys, artifacts & media…');
      log.add('⏳ Building backup payload…');
      final Map<String, dynamic> backupData;
      try {
        backupData = await _buildBackupPayload(sessions, prefs);
      } catch (e) {
        log.add('❌ Payload build failed: $e');
        return DriveSyncResult(
          success: false,
          message: 'Failed to collect backup data: $e',
          details: log,
        );
      }
      final sessionCount = sessions.length;
      final artifactCount = backupData['artifact_count'] ?? 0;
      final keyCount = backupData['provider_api_key_count'] ?? 0;
      log.add(
        '✅ Payload ready — $sessionCount chats, $artifactCount artifacts, $keyCount keys',
      );

      // ── Step 3: encode ──
      onProgress?.call('Encoding backup ($sessionCount chats, $artifactCount artifacts)…');
      log.add('⏳ Encoding JSON…');
      final jsonBackup = jsonEncode(backupData);
      final bytes = utf8.encode(jsonBackup);
      final sizeKB = (bytes.length / 1024).toStringAsFixed(1);
      log.add('✅ Encoded — ${sizeKB} KB');

      // ── Step 4: find existing file ──
      onProgress?.call('Checking for existing backup on Drive…');
      log.add('⏳ Searching for existing backup file…');
      drive.File? existing;
      String? folderId;
      try {
        final lookup = await _withDriveAuthRetry(
          (driveApi) async {
            final id = await _getOrCreateBackupFolder(driveApi);
            return _BackupLookup(
              folderId: id,
              existing: await _findBackupFile(driveApi, id),
            );
          },
          log,
        );
        folderId = lookup.folderId;
        existing = lookup.existing;
      } catch (e) {
        _appendDriveFailure(log, 'Drive search', e);
        return DriveSyncResult(
          success: false,
          needsRelogin: _needsReloginForError(e),
          message: _driveErrorMessage('Failed to search Drive', e),
          details: log,
        );
      }
      log.add(existing?.id != null
          ? '✅ Found existing backup — updating'
          : '✅ No existing backup — creating new file');

      // Check if backup is already identical (up to date)
      if (existing?.id != null && existing?.md5Checksum != null) {
        final localMd5 = md5.convert(bytes).toString().toLowerCase();
        final remoteMd5 = existing!.md5Checksum!.toLowerCase();
        if (localMd5 == remoteMd5) {
          log.add('ℹ️ Backup on Drive is already up to date (MD5: $localMd5). Skipping upload.');
          onProgress?.call('Backup is already up to date ✅');
          return DriveSyncResult(
            success: true,
            message: 'Backup is already up to date (no changes detected).',
            details: log,
          );
        }
      }

      // ── Step 5: upload ──
      onProgress?.call('Uploading ${sizeKB} KB to Google Drive…');
      log.add('⏳ Uploading…');
      try {
        await _withDriveAuthRetry((driveApi) async {
          // Build a fresh stream for the one permitted auth retry.
          final upload = drive.Media(Stream.value(bytes), bytes.length);
          if (existing?.id != null) {
            await driveApi.files.update(
              drive.File()
                ..name = _backupFileName
                ..modifiedTime = DateTime.now().toUtc(),
              existing!.id!,
              uploadMedia: upload,
            );
          } else {
            await driveApi.files.create(
              drive.File()
                ..name = _backupFileName
                ..parents = [folderId],
              uploadMedia: upload,
            );
          }
        }, log);
      } catch (e) {
        _appendDriveFailure(log, 'Upload', e);
        return DriveSyncResult(
          success: false,
          needsRelogin: _needsReloginForError(e),
          message: _driveErrorMessage('Upload to Drive failed', e),
          details: log,
        );
      }
      log.add('✅ Upload complete');

      // ── Done ──
      onProgress?.call('Backup complete ✅');
      final msg =
          'Backed up $sessionCount chat(s), $artifactCount artifact(s), '
          '$keyCount provider key(s), settings & memory (${sizeKB} KB).';
      log.add('✅ $msg');
      return DriveSyncResult(success: true, message: msg, details: log);
    } catch (e) {
      _appendDriveFailure(log, 'Backup', e);
      return DriveSyncResult(
        success: false,
        needsRelogin: _needsReloginForError(e),
        message: _driveErrorMessage('Backup failed', e),
        details: log,
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // RESTORE (download from Drive)
  // ──────────────────────────────────────────────────────────────────
  static Future<DriveSyncResult> restoreFromDriveDetailed({
    SyncProgressCallback? onProgress,
  }) async {
    final log = <String>[];
    final prefs = await SharedPreferences.getInstance();

    // ── Step 1: authenticate ──
    onProgress?.call('Authenticating with Google Drive…');
    log.add('⏳ Authenticating…');
    final tokenResult = await _getValidGoogleToken();
    if (tokenResult.error != null) {
      log.add('❌ Auth failed: ${tokenResult.error}');
      return DriveSyncResult(
        success: false,
        needsRelogin: tokenResult.needsRelogin,
        message: tokenResult.error!,
        details: log,
      );
    }
    log.add('✅ Authenticated');

    try {
      // ── Step 2: find backup file ──
      onProgress?.call('Searching for backup on Drive…');
      log.add('⏳ Looking for backup file…');
      drive.File? existing;
      try {
        existing = await _withDriveAuthRetry((driveApi) async {
          final folderList = await driveApi.files.list(
            spaces: 'drive',
            q: "mimeType = 'application/vnd.google-apps.folder' and name = 'Nexon Backups' and trashed = false",
            $fields: 'files(id)',
            pageSize: 1,
          );
          if (folderList.files?.isEmpty != false) return null;
          return _findBackupFile(driveApi, folderList.files!.first.id!);
        }, log);
      } catch (e) {
        _appendDriveFailure(log, 'Drive search', e);
        return DriveSyncResult(
          success: false,
          needsRelogin: _needsReloginForError(e),
          message: _driveErrorMessage('Failed to search Drive', e),
          details: log,
        );
      }
      if (existing?.id == null) {
        log.add('⚠️ No backup file found on Drive');
        return DriveSyncResult(
          success: false,
          message: 'No Google Drive backup found for this app.',
          details: log,
        );
      }
      log.add('✅ Found backup file (id: ${existing!.id})');

      // ── Step 3: download ──
      onProgress?.call('Downloading backup…');
      log.add('⏳ Downloading…');
      Map<String, dynamic> backupData;
      try {
        final bytes = await _withDriveAuthRetry((driveApi) async {
          final response = await driveApi.files.get(
                existing!.id!,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;
          final downloaded = <int>[];
          await for (final chunk in response.stream) {
            downloaded.addAll(chunk);
          }
          return downloaded;
        }, log);
        final sizeKB = (bytes.length / 1024).toStringAsFixed(1);
        log.add('✅ Downloaded ${sizeKB} KB');

        onProgress?.call('Parsing backup data…');
        log.add('⏳ Parsing JSON…');
        backupData = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        log.add('✅ Parsed — version ${backupData['version'] ?? 'unknown'}');
      } catch (e) {
        _appendDriveFailure(log, 'Download/parse', e);
        return DriveSyncResult(
          success: false,
          needsRelogin: _needsReloginForError(e),
          message: _driveErrorMessage('Failed to download or parse backup', e),
          details: log,
        );
      }

      // ── Step 4: restore chats ──
      onProgress?.call('Restoring chats…');
      log.add('⏳ Restoring chats…');
      try {
        await _restorePrefsString(
          prefs,
          backupData,
          'chat_sessions',
          'chat_sessions_v1',
        );
        final chatCount = (backupData['chat_sessions'] is List)
            ? (backupData['chat_sessions'] as List).length
            : 0;
        log.add('✅ Restored $chatCount chat session(s)');
      } catch (e) {
        log.add('⚠️ Chat restore error (non-fatal): $e');
      }

      // ── Step 5: restore settings ──
      onProgress?.call('Restoring settings…');
      log.add('⏳ Restoring settings…');
      try {
        await _restorePrefsString(
          prefs,
          backupData,
          'provider_settings',
          'provider_settings_v1',
        );
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
        log.add('✅ Settings restored');
      } catch (e) {
        log.add('⚠️ Settings restore error (non-fatal): $e');
      }

      // ── Step 6: restore API keys ──
      onProgress?.call('Restoring API keys…');
      log.add('⏳ Restoring provider API keys…');
      try {
        await _restoreProviderApiKeys(prefs, backupData['provider_api_keys']);
        final keyCount = backupData['provider_api_key_count'] ?? '?';
        log.add('✅ Restored $keyCount provider key(s)');
      } catch (e) {
        log.add('⚠️ API key restore error (non-fatal): $e');
      }

      // ── Step 7: restore memory ──
      onProgress?.call('Restoring AI memory…');
      log.add('⏳ Restoring AI memory…');
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final aiMemory = backupData['ai_memory'];
        if (aiMemory != null && aiMemory.toString().isNotEmpty) {
          await File(
            '${docDir.path}/nexon_memory.json',
          ).writeAsString(aiMemory.toString());
          log.add('✅ Memory restored');
        } else {
          log.add('ℹ️ No memory data in backup');
        }
      } catch (e) {
        log.add('⚠️ Memory restore error (non-fatal): $e');
      }

      // ── Step 8: restore artifacts ──
      onProgress?.call('Restoring artifacts…');
      log.add('⏳ Restoring artifacts…');
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final artifactCount = await _restoreArtifacts(
          docDir,
          backupData['artifacts'],
        );
        log.add('✅ Restored $artifactCount artifact(s)');
      } catch (e) {
        log.add('⚠️ Artifact restore error (non-fatal): $e');
      }

      // ── Done ──
      onProgress?.call('Restore complete ✅');
      log.add('✅ Restore finished successfully');
      return DriveSyncResult(
        success: true,
        message:
            'Restore complete. Chats, provider keys, settings, memory, and artifacts were restored.',
        details: log,
      );
    } catch (e) {
      _appendDriveFailure(log, 'Restore', e);
      return DriveSyncResult(
        success: false,
        needsRelogin: _needsReloginForError(e),
        message: _driveErrorMessage('Restore failed', e),
        details: log,
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // TOKEN MANAGEMENT — the critical fix
  // ──────────────────────────────────────────────────────────────────
  /// Gets the current provider token. Expiry is tracked once Google returns an
  /// `expires_in` value; otherwise the Drive-operation wrapper detects a 401
  /// and performs one refresh/retry without exposing a dialog to the user.
  static Future<_TokenResult> _getValidGoogleToken({
    bool forceRefresh = false,
    List<String>? diagnostics,
  }) async {
    final session = Supabase.instance.client.auth.currentSession;
    final liveToken = session?.providerToken;
    final liveRefresh = session?.providerRefreshToken;
    if ((liveToken?.isNotEmpty ?? false) || (liveRefresh?.isNotEmpty ?? false)) {
      await _storeGoogleTokens(
        accessToken: liveToken,
        refreshToken: liveRefresh,
      );
    }

    final stored = await _readGoogleTokens();
    final token = liveToken?.isNotEmpty == true ? liveToken : stored.accessToken;
    final expiry = stored.expiry;
    final expired = expiry != null && !expiry.isAfter(DateTime.now().toUtc());
    if (!forceRefresh && token != null && token.isNotEmpty && !expired) {
      return _TokenResult(token: token);
    }

    final refresh = stored.refreshToken ?? liveRefresh;
    final refreshResult = await _refreshGoogleAccessToken(refresh, diagnostics);
    if (refreshResult.token != null) {
      return _TokenResult(token: refreshResult.token);
    }
    return _TokenResult(
      error: refreshResult.error ?? 'Google Drive authentication is unavailable.',
      needsRelogin: refreshResult.needsRelogin,
    );
  }

  /// Exchanges the Google provider refresh token for a new Drive token.
  /// A Supabase session refresh token cannot perform this exchange and must
  /// never be substituted for the Google provider refresh token.
  static Future<_RefreshResult> _refreshGoogleAccessToken(
    String? refreshToken,
    List<String>? diagnostics,
  ) async {
    if (refreshToken == null || refreshToken.isEmpty) {
      diagnostics?.add('❌ No stored Google provider refresh token');
      return const _RefreshResult(
        error: 'Google authorization was not granted for offline access. Please sign in again.',
        needsRelogin: true,
      );
    }
    if (_googleOAuthClientId.isEmpty) {
      diagnostics?.add('❌ GOOGLE_OAUTH_CLIENT_ID is not configured');
      return const _RefreshResult(
        error: 'Google Drive refresh is not configured in this build.',
      );
    }

    try {
      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': _googleOAuthClientId,
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
        },
      ).timeout(const Duration(seconds: 15));
      final body = response.body;
      if (response.statusCode == 200) {
        final payload = jsonDecode(body) as Map<String, dynamic>;
        final accessToken = payload['access_token'] as String?;
        if (accessToken == null || accessToken.isEmpty) {
          return const _RefreshResult(error: 'Google did not return an access token.');
        }
        final expiresIn = payload['expires_in'];
        final expiry = expiresIn is num
            ? DateTime.now().toUtc().add(Duration(seconds: expiresIn.toInt()))
            : null;
        await _storeGoogleTokens(accessToken: accessToken, expiry: expiry);
        diagnostics?.add('✅ Google Drive token refreshed silently');
        return _RefreshResult(token: accessToken);
      }

      final failure = _DriveFailure.fromResponse(response.statusCode, body);
      _debugDriveFailure('Google refresh', failure);
      if (failure.invalidGrant) {
        return const _RefreshResult(
          error: 'Google Drive authorization was revoked or expired. Please sign in again.',
          needsRelogin: true,
        );
      }
      return _RefreshResult(error: 'Unable to refresh Google Drive access (${failure.label}).');
    } catch (e) {
      debugPrint('[drive-token-refresh] request failed: $e');
      return const _RefreshResult(error: 'Could not contact Google to refresh Drive access.');
    }
  }

  static Future<_StoredGoogleTokens> _readGoogleTokens() async {
    var accessToken = await _secureStorage.read(key: _tokenKey);
    var refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    final expiryRaw = await _secureStorage.read(key: _tokenExpiryKey);
    DateTime? expiry;
    if (expiryRaw != null) expiry = DateTime.tryParse(expiryRaw)?.toUtc();

    // One-time migration from the legacy insecure SharedPreferences keys.
    if (accessToken == null || refreshToken == null) {
      final prefs = await SharedPreferences.getInstance();
      accessToken ??= prefs.getString(_tokenKey);
      refreshToken ??= prefs.getString(_refreshTokenKey);
      if (accessToken != null || refreshToken != null) {
        await _storeGoogleTokens(
          accessToken: accessToken,
          refreshToken: refreshToken,
          expiry: expiry,
          removeLegacy: false,
        );
      }
      await prefs.remove(_tokenKey);
      await prefs.remove(_refreshTokenKey);
    }
    return _StoredGoogleTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiry: expiry,
    );
  }

  static Future<void> _storeGoogleTokens({
    String? accessToken,
    String? refreshToken,
    DateTime? expiry,
    bool removeLegacy = true,
  }) async {
    if (accessToken != null && accessToken.isNotEmpty) {
      await _secureStorage.write(key: _tokenKey, value: accessToken);
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
    }
    if (expiry != null) {
      await _secureStorage.write(
        key: _tokenExpiryKey,
        value: expiry.toUtc().toIso8601String(),
      );
    }
    if (removeLegacy) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_refreshTokenKey);
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Drive file lookup
  // ──────────────────────────────────────────────────────────────────
  /// Gets or creates a visible "Nexon Backups" folder in the user's Drive.
  static Future<String> _getOrCreateBackupFolder(drive.DriveApi driveApi) async {
    final folderList = await driveApi.files.list(
      spaces: 'drive',
      q: "mimeType = 'application/vnd.google-apps.folder' and name = 'Nexon Backups' and trashed = false",
      $fields: 'files(id)',
      pageSize: 1,
    );
    if (folderList.files?.isNotEmpty == true) {
      return folderList.files!.first.id!;
    }
    // Create the folder
    final folder = await driveApi.files.create(
      drive.File()
        ..name = 'Nexon Backups'
        ..mimeType = 'application/vnd.google-apps.folder',
    );
    return folder.id!;
  }

  static Future<drive.File?> _findBackupFile(drive.DriveApi driveApi, String folderId) async {
    final files = await driveApi.files.list(
      spaces: 'drive',
      q: "name = '$_backupFileName' and '$folderId' in parents and trashed = false",
      $fields: 'files(id,name,modifiedTime,size,md5Checksum)',
      pageSize: 1,
    );
    return files.files?.isNotEmpty == true ? files.files!.first : null;
  }

  // ──────────────────────────────────────────────────────────────────
  // Backup payload builder
  // ──────────────────────────────────────────────────────────────────
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

  // ──────────────────────────────────────────────────────────────────
  // Provider API key collection
  // ──────────────────────────────────────────────────────────────────
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

  // ──────────────────────────────────────────────────────────────────
  // Artifact collection
  // ──────────────────────────────────────────────────────────────────
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
          final isMedia = _mediaExtensions.contains(ext);

          // Skip unknown binary formats to keep backup size reasonable.
          if (!isText && !isMedia && ext.isNotEmpty) continue;

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

  // ──────────────────────────────────────────────────────────────────
  // Artifact restoration — returns the count of restored artifacts
  // ──────────────────────────────────────────────────────────────────
  static Future<int> _restoreArtifacts(
    Directory docDir,
    Object? artifactsData,
  ) async {
    if (artifactsData == null) return 0;
    final Map<String, dynamic> raw;
    try {
      if (artifactsData is String) {
        if (artifactsData.trim().isEmpty) return 0;
        final decoded = jsonDecode(artifactsData);
        if (decoded is! Map) return 0;
        raw = Map<String, dynamic>.from(decoded);
      } else if (artifactsData is Map) {
        raw = Map<String, dynamic>.from(artifactsData);
      } else {
        return 0;
      }
    } catch (_) {
      return 0;
    }

    int count = 0;
    for (final entry in raw.entries) {
      final safeRel = _safeRelativePath(entry.key);
      if (safeRel == null) continue;
      final targetRel = safeRel.contains('/') ? safeRel : 'brain/$safeRel';
      final file = File('${docDir.path}/$targetRel');
      try {
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
        count++;
      } catch (_) {
        continue;
      }
    }
    return count;
  }

  // ──────────────────────────────────────────────────────────────────
  // Preference restoration helpers
  // ──────────────────────────────────────────────────────────────────
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

  // ──────────────────────────────────────────────────────────────────
  // Path helpers
  // ──────────────────────────────────────────────────────────────────
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

  /// Check if an error indicates an auth/permission problem.
  static bool _isAuthError(Object e) {
    final text = e.toString().toLowerCase();
    return text.contains('401') ||
        text.contains('403') ||
        text.contains('unauthorized') ||
        text.contains('insufficient');
  }

  static Future<T> _withDriveAuthRetry<T>(
    Future<T> Function(drive.DriveApi driveApi) operation,
    List<String> log,
  ) async {
    var tokenResult = await _getValidGoogleToken(diagnostics: log);
    if (tokenResult.error != null) {
      throw drive.DetailedApiRequestError(401, tokenResult.error!);
    }

    var client = GoogleAuthClient(tokenResult.token!);
    var driveApi = drive.DriveApi(client);

    try {
      return await operation(driveApi);
    } catch (e) {
      if (e is drive.DetailedApiRequestError && e.status == 401) {
        log.add('⚠️ API request failed with 401. Attempting token refresh...');
        client.close();

        final refreshResult = await _getValidGoogleToken(forceRefresh: true, diagnostics: log);
        if (refreshResult.error != null) {
          log.add('❌ Token refresh failed during retry: ${refreshResult.error}');
          throw drive.DetailedApiRequestError(401, refreshResult.error!);
        }

        log.add('🔄 Retrying operation with refreshed access token...');
        client = GoogleAuthClient(refreshResult.token!);
        driveApi = drive.DriveApi(client);
        try {
          return await operation(driveApi);
        } catch (retryError) {
          client.close();
          rethrow;
        }
      } else {
        client.close();
        rethrow;
      }
    } finally {
      client.close();
    }
  }

  static bool _needsReloginForError(Object e) {
    if (e is drive.DetailedApiRequestError) {
      return e.status == 401;
    }
    final text = e.toString().toLowerCase();
    if (text.contains('invalid_grant')) {
      return true;
    }
    return text.contains('401');
  }

  static String _driveErrorMessage(String prefix, Object e) {
    if (e is drive.DetailedApiRequestError) {
      if (e.status == 401) {
        return '$prefix: Google Drive session expired. Please sign out and sign in again.';
      }
      if (e.status == 403) {
        final message = e.message ?? '';
        if (message.toLowerCase().contains('disabled') || message.toLowerCase().contains('not enabled')) {
          return '$prefix: Google Drive API has not been enabled in your Google Console project. Please enable it in the Google Cloud Console.';
        }
        return '$prefix: Access denied (403 Forbidden). Check your Google account permissions or scopes.';
      }
      if (e.status == 429) {
        return '$prefix: Google Drive API rate limit exceeded (429 Too Many Requests). Please retry in a few minutes.';
      }
      return '$prefix: Google Drive API error (${e.status}): ${e.message}';
    }
    return '$prefix: ${e.toString()}';
  }

  static void _appendDriveFailure(List<String> log, String context, Object e) {
    if (e is drive.DetailedApiRequestError) {
      log.add('❌ $context failed (HTTP ${e.status}): ${e.message}');
    } else {
      log.add('❌ $context failed: $e');
    }
  }

  static void _debugDriveFailure(String context, _DriveFailure failure) {
    debugPrint('[drive-sync] $context failure: ${failure.label} (invalidGrant: ${failure.invalidGrant})');
  }
}

/// Internal result type for token acquisition.
class _TokenResult {
  _TokenResult({this.token, this.error, this.needsRelogin = false});
  final String? token;
  final String? error;
  final bool needsRelogin;
}

class _BackupLookup {
  const _BackupLookup({required this.folderId, this.existing});
  final String folderId;
  final drive.File? existing;
}

class _StoredGoogleTokens {
  const _StoredGoogleTokens({this.accessToken, this.refreshToken, this.expiry});
  final String? accessToken;
  final String? refreshToken;
  final DateTime? expiry;
}

class _RefreshResult {
  const _RefreshResult({this.token, this.error, this.needsRelogin = false});
  final String? token;
  final String? error;
  final bool needsRelogin;
}

class _DriveFailure {
  const _DriveFailure({
    required this.statusCode,
    required this.message,
    this.invalidGrant = false,
  });

  final int statusCode;
  final String message;
  final bool invalidGrant;

  String get label => 'HTTP $statusCode: $message';

  factory _DriveFailure.fromResponse(int statusCode, String body) {
    bool isInvalidGrant = false;
    String errMsg = body;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final err = decoded['error'];
        final desc = decoded['error_description'] ?? decoded['message'];
        if (err != null) {
          errMsg = '$err${desc != null ? ": $desc" : ""}';
          if (err.toString().toLowerCase() == 'invalid_grant' ||
              desc.toString().toLowerCase().contains('invalid_grant')) {
            isInvalidGrant = true;
          }
        }
      }
    } catch (_) {}
    return _DriveFailure(
      statusCode: statusCode,
      message: errMsg,
      invalidGrant: isInvalidGrant,
    );
  }
}

