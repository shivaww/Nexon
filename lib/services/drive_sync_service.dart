import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

List<int> _gzipBackupBytes(List<int> bytes) => gzip.encode(bytes);

Future<List<int>> _gunzipBackupBytes(List<int> bytes) async {
  const maxExpandedBytes = 256 * 1024 * 1024;
  final output = BytesBuilder(copy: false);
  var expandedLength = 0;
  await for (final chunk in gzip.decoder.bind(Stream<List<int>>.value(bytes))) {
    expandedLength += chunk.length;
    if (expandedLength > maxExpandedBytes) {
      throw const FormatException('Backup expands beyond the supported size.');
    }
    output.add(chunk);
  }
  return output.takeBytes();
}

Object? _canonicalJsonValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, dynamic>{
      for (final key in keys) key: _canonicalJsonValue(value[key]),
    };
  }
  if (value is Iterable) return value.map(_canonicalJsonValue).toList();
  return value;
}

String _hashBackupPayload(Map<String, dynamic> backupData) {
  final digestData = Map<String, dynamic>.from(backupData)
    ..remove('created_at');
  return sha256
      .convert(utf8.encode(jsonEncode(_canonicalJsonValue(digestData))))
      .toString();
}

/// HTTP client that injects a Bearer token only into Google Drive API calls.
class GoogleAuthClient extends http.BaseClient {
  GoogleAuthClient(this._token);

  final String _token;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.scheme != 'https' ||
        request.url.host != 'www.googleapis.com') {
      throw StateError(
        'Refusing to send Google Drive credentials to an unexpected host.',
      );
    }
    request.followRedirects = false;
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
  static const _backupFileName = 'nexon_backup.enc';
  static const _tokenKey = 'google_provider_token';
  static const _refreshTokenKey = 'google_provider_refresh_token';
  static const _tokenExpiryKey = 'google_provider_token_expiry';
  // V1 keys are retained only so existing same-device backups remain readable.
  static const _encryptionKeyStorage = 'nexon_backup_enc_key';
  static const _encryptionKeyStorageV2 = 'nexon_backup_enc_key_v2';
  static const _backupV1Header = 'NEXON_ENC_V1:';
  static const _backupV2Header = 'NEXON_AESGCM_V2:';
  static const _backupV3Header = 'NEXON_GZIP_AESGCM_V3:';
  static const _backupV2NonceBytes = 12;
  static const _backupV2MacBytes = 16;
  static final _backupCipher = AesGcm.with256bits();
  static Future<List<int>>? _creatingBackupKeyV2;
  static const _maxBackupVersions = 5;
  // Public OAuth client identifier for Google Drive token refresh.
  // Matches the Google OAuth Web Client ID configured in Supabase Auth.
  static const _googleOAuthClientId =
      '324056833787-tvm3a99dvsnt9hhpfht8saub1hnegkkj.apps.googleusercontent.com';
  // Web-type OAuth clients require the client secret for refresh grants.
  // Value: Google Cloud Console > APIs & Services > Credentials > your Web client.
  static const _googleOAuthClientSecret = '';
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
    final expiry = (token != null && token.isNotEmpty)
        ? DateTime.now().toUtc().add(const Duration(minutes: 55))
        : null;
    await _storeGoogleTokens(
      accessToken: token,
      refreshToken: refresh,
      expiry: expiry,
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Public convenience wrappers (legacy API, no progress)
  // ──────────────────────────────────────────────────────────────────
  /// Guards against multiple concurrent auto-syncs.
  static bool _isSyncing = false;
  static Future<void> _driveSyncTail = Future<void>.value();
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
        if (_isSyncing) {
          _pendingSessions = toSync;
          _pendingDebounce = Future.delayed(
            const Duration(seconds: 10),
            () async {
              _pendingDebounce = null;
              final retry = _pendingSessions;
              _pendingSessions = null;
              if (retry == null) return;
              _isSyncing = true;
              try {
                await syncToDriveDetailed(retry, force: false);
              } finally {
                _isSyncing = false;
              }
            },
          );
          return;
        }
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

  /// Private app storage for the full local chat history. Chat content should
  /// not be written under the user-selected workspace, which may be a repo.
  static Future<File> sessionBackupFile() async {
    final docs = await getApplicationDocumentsDirectory();
    final directory = Directory('${docs.path}/.nexon/sessions');
    await directory.create(recursive: true);
    return File('${directory.path}/prefs_backup.json');
  }

  static Future<void> _writeSessionBackup(File backupFile, String json) async {
    await backupFile.parent.create(recursive: true);
    final tmp = File(
      '${backupFile.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(backupFile.path);
  }

  static Future<List<File>> _legacySessionBackupFiles(
    SharedPreferences prefs,
  ) async {
    final docs = await getApplicationDocumentsDirectory();
    var workspace = (prefs.getString('agentic_workspace_v1') ??
            '/data/data/com.termux/files/home')
        .trim();
    if (workspace.isEmpty) {
      workspace = '/data/data/com.termux/files/home';
    }
    final home = Platform.environment['HOME'] ??
        '/data/data/com.termux/files/home';
    if (workspace == '~') {
      workspace = home;
    } else if (workspace.startsWith('~/')) {
      workspace = '$home/${workspace.substring(2)}';
    }
    workspace = workspace.replaceAll(RegExp(r'/+$'), '');
    return [
      File('$workspace/.nexon/sessions/prefs_backup.json'),
      File('${docs.path}/sessions/prefs_backup.json'),
    ];
  }

  static Future<void> _removeLegacySessionBackupFiles(
    SharedPreferences prefs,
  ) async {
    final current = await sessionBackupFile();
    for (final file in await _legacySessionBackupFiles(prefs)) {
      if (file.path == current.path) continue;
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // BACKUP (upload to Drive)
  // ──────────────────────────────────────────────────────────────────
  static Future<DriveSyncResult> syncToDriveDetailed(
    List<dynamic> sessions, {
    bool force = false,
    SyncProgressCallback? onProgress,
  }) async {
    final snapshot = List<dynamic>.from(sessions);
    final previous = _driveSyncTail;
    final release = Completer<void>();
    _driveSyncTail = release.future;
    try {
      try {
        await previous;
      } catch (_) {
        // A failed prior sync must not block later backups.
      }
      final result = await _performSyncToDriveDetailed(
        snapshot,
        force: force,
        onProgress: onProgress,
      );
      if (result.success) {
        // A good backup pushes the weekly reminder out another week.
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(
            'backup_reminder_next_ms',
            DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch,
          );
        } catch (_) {}
      }
      return result;
    } finally {
      release.complete();
    }
  }

  static Future<DriveSyncResult> _performSyncToDriveDetailed(
    List<dynamic> sessions, {
    required bool force,
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

      final contentHash = await compute(
        _hashBackupPayload,
        backupData,
        debugLabel: 'fingerprint chat backup',
      );

      // ── Step 3: find existing file ──
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
      if (existing?.id != null &&
          existing!.appProperties?['contentHash'] == contentHash) {
        log.add('✅ Backup is unchanged; skipped upload');
        return DriveSyncResult(
          success: true,
          message: 'Backup is already up to date; upload skipped.',
          details: log,
        );
      }
      log.add(existing?.id != null
          ? '✅ Found existing backup — creating new version'
          : '✅ No existing backup — creating new file');

      // Delay compression and encryption until after the fingerprint check so
      // an unchanged backup costs neither upload data nor compression work.
      onProgress?.call('Compressing and encrypting backup…');
      log.add('⏳ Compressing and encrypting…');
      final rawBytes = utf8.encode(jsonEncode(backupData));
      final compressedBytes = await compute(
        _gzipBackupBytes,
        rawBytes,
        debugLabel: 'compress chat backup',
      );
      final bytes = await _encryptBackup(compressedBytes);
      final sizeKB = (bytes.length / 1024).toStringAsFixed(1);
      log.add('✅ Compressed and encrypted — ${sizeKB} KB');

      final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
      final versionedName = 'nexon_backup_$timestamp.enc';

      try {
        await _withDriveAuthRetry((driveApi) async {
          final upload = drive.Media(Stream.value(bytes), bytes.length);
          await driveApi.files.create(
            drive.File()
              ..name = versionedName
              ..parents = [folderId!]
              ..appProperties = {'contentHash': contentHash},
            uploadMedia: upload,
          );
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

      try {
        await _withDriveAuthRetry((driveApi) async {
          final backupFiles = await _listBackupFiles(driveApi, folderId!);
          for (final oldFile in backupFiles.skip(_maxBackupVersions)) {
            final id = oldFile.id;
            if (id == null || id == existing?.id) continue;
            try {
              await driveApi.files.delete(id);
            } catch (_) {}
          }
        }, log);
      } catch (_) {}
      log.add('✅ Upload complete');

      // ── Done ──
      onProgress?.call('Backup complete ✅ (encrypted)');
      final msg =
          'Backed up $sessionCount chat(s), $artifactCount artifact(s), '
          '$keyCount provider key(s) & settings (${sizeKB} KB, encrypted).';
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
            spaces: 'appDataFolder',
            q: "mimeType = 'application/vnd.google-apps.folder' and name = 'nexon_data' and trashed = false",
            $fields: 'files(id)',
            pageSize: 1,
          );
          if (folderList.files?.isEmpty != false) return null;
          final folderId = folderList.files!.first.id!;
          return _findBackupFile(driveApi, folderId);
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
          final downloaded = BytesBuilder(copy: false);
          await for (final chunk in response.stream) {
            downloaded.add(chunk);
          }
          return downloaded.takeBytes();
        }, log);
        final sizeKB = (bytes.length / 1024).toStringAsFixed(1);
        log.add('✅ Downloaded ${sizeKB} KB');

        onProgress?.call('Decrypting backup data…');
        log.add('⏳ Decrypting…');
        final decryptedBytes = await _decryptBackup(bytes);
        if (decryptedBytes == null) {
          log.add('❌ Decryption failed — backup may be from a different device or corrupted.');
          return DriveSyncResult(
            success: false,
            message: 'Backup decryption failed. The encryption key on this device does not match.',
            details: log,
          );
        }
        log.add('✅ Decrypted');
        final jsonBytes = _hasPrefix(bytes, utf8.encode(_backupV3Header))
            ? await compute(
                _gunzipBackupBytes,
                decryptedBytes,
                debugLabel: 'decompress chat backup',
              )
            : decryptedBytes;
        backupData = jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
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

      // ── Step 4: restore & merge chats ──
      onProgress?.call('Merging chats from Drive…');
      log.add('⏳ Merging chats…');
      var chatRestoreFailed = false;
      try {
        final totalCount = await _mergeAndRestoreChatSessions(
          prefs,
          backupData,
          log,
        );
        log.add('✅ Restored & merged $totalCount chat session(s)');
      } catch (_) {
        chatRestoreFailed = true;
        log.add('⚠️ Chat restore failed; other backup data will still be restored.');
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
        await _restorePrefsString(
          prefs,
          backupData,
          'custom_providers',
          'custom_providers_v1',
        );
        await _restorePrefsString(
          prefs,
          backupData,
          'user_name',
          'user_name_v1',
        );
        await _restorePrefsBool(
          prefs,
          backupData,
          'study_mode_enabled',
          'study_mode_enabled_v1',
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

      // ── Step 7: restore artifacts ──
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
      if (chatRestoreFailed) {
        log.add('⚠️ Restore finished with chat history not saved.');
        return DriveSyncResult(
          success: false,
          message:
              'Other backup data was restored, but chat history could not be saved locally.',
          details: log,
        );
      }
      log.add('✅ Restore finished successfully');
      return DriveSyncResult(
        success: true,
        message:
            'Restore complete. Chats, API keys, settings, and artifacts restored (existing data preserved).',
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
  /// `expires_in` value or sign-in occurs; otherwise the Drive-operation wrapper detects a 401
  /// and performs silent refresh without requiring user re-authentication.
  static Future<_TokenResult> _getValidGoogleToken({
    bool forceRefresh = false,
    List<String>? diagnostics,
  }) async {
    final session = Supabase.instance.client.auth.currentSession;
    final liveToken = session?.providerToken;
    final liveRefresh = session?.providerRefreshToken;

    // Persist only genuinely new sign-in tokens. Never rewrite expiry for
    // a stale session token — that resurrects dead tokens as "valid".
    var stored = await _readGoogleTokens();
    if (liveToken != null &&
        liveToken.isNotEmpty &&
        liveToken != stored.accessToken) {
      await _storeGoogleTokens(
        accessToken: liveToken,
        refreshToken: liveRefresh,
        expiry: DateTime.now().toUtc().add(const Duration(minutes: 55)),
      );
      stored = await _readGoogleTokens();
    } else if (liveRefresh != null &&
        liveRefresh.isNotEmpty &&
        stored.refreshToken?.isNotEmpty != true) {
      await _storeGoogleTokens(refreshToken: liveRefresh);
    }
    final refreshToken = stored.refreshToken?.isNotEmpty == true
        ? stored.refreshToken
        : (liveRefresh?.isNotEmpty == true ? liveRefresh : null);

    final now = DateTime.now().toUtc();
    final bool isExpired = stored.expiry == null || !stored.expiry!.isAfter(now);

    // If stored token exists, is valid (not expired), and forceRefresh is false, use it
    if (!forceRefresh && stored.accessToken != null && stored.accessToken!.isNotEmpty && !isExpired) {
      return _TokenResult(token: stored.accessToken);
    }

    // Token is expired, missing, or forceRefresh requested -> Perform silent refresh
    diagnostics?.add('⏳ Token expired or refresh requested. Attempting silent Google token refresh…');
    final refreshResult = await _refreshGoogleAccessToken(refreshToken, diagnostics);
    if (refreshResult.token != null) {
      return _TokenResult(token: refreshResult.token);
    }

    // Fallback: If refresh failed but a token is available, attempt it as last resort
    final candidateToken = stored.accessToken ?? (liveToken?.isNotEmpty == true ? liveToken : null);
    if (candidateToken != null && candidateToken.isNotEmpty && !forceRefresh) {
      diagnostics?.add('⚠️ Silent refresh failed; attempting existing token as fallback…');
      return _TokenResult(token: candidateToken);
    }

    return _TokenResult(
      error: refreshResult.error ?? 'Google Drive authentication is unavailable. Please sign in again.',
      needsRelogin: refreshResult.needsRelogin,
    );
  }

  /// Exchanges the Google provider refresh token for a new Drive token.
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

    // 1. Nexon backend (Render): server-side secret exchange. Only the
    // refresh token travels — backup data never touches the backend.
    final jwtToken = Supabase.instance.client.auth.currentSession?.accessToken;
    final backendClient = http.Client();
    Future<http.Response> renderCall(Duration t) async {
      final request = http.Request(
        'POST',
        Uri.parse(
          'https://nexon-jyp1.onrender.com/api/refresh-google-drive-token',
        ),
      )
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({'refresh_token': refreshToken});
      if (jwtToken != null && jwtToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $jwtToken';
      }
      final streamed = await backendClient.send(request).timeout(t);
      return http.Response.fromStream(streamed).timeout(t);
    }
    try {
      http.Response response;
      try {
        response = await renderCall(const Duration(seconds: 12));
      } on TimeoutException {
        diagnostics?.add('⏳ Backend waking (cold start), retrying…');
        response = await renderCall(const Duration(seconds: 45));
      }
      if (response.statusCode == 200) {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        final accessToken = payload['access_token'] as String?;
        if (accessToken != null && accessToken.isNotEmpty) {
          final expiresIn = payload['expires_in'];
          final expirySeconds = (expiresIn is num && expiresIn > 120)
              ? expiresIn.toInt() - 120
              : 3000;
          await _storeGoogleTokens(
            accessToken: accessToken,
            refreshToken: payload['refresh_token'] as String?,
            expiry: DateTime.now().toUtc().add(Duration(seconds: expirySeconds)),
          );
          diagnostics?.add('✅ Refreshed Google token via Nexon backend');
          return _RefreshResult(token: accessToken);
        }
      }
      final body = response.body;
      diagnostics?.add('⚠️ Backend refresh failed (${response.statusCode}).');
      if (body.contains('invalid_grant')) {
        return const _RefreshResult(
          error: 'Google Drive authorization was revoked or expired. Please sign in again.',
          needsRelogin: true,
        );
      }
    } catch (e) {
      diagnostics?.add('⚠️ Backend refresh attempt failed (${e.runtimeType}).');
    } finally {
      backendClient.close();
    }

    // 2. Delegate token refresh to server-side Supabase Edge Function refresh-google-drive-token
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'refresh-google-drive-token',
        body: {'refresh_token': refreshToken},
      ).timeout(const Duration(seconds: 30));
      final data = res.data;
      if (res.status == 200 && data != null) {
        final payload = data is Map<String, dynamic>
            ? data
            : (data is Map
                ? Map<String, dynamic>.from(data)
                : jsonDecode(data.toString()) as Map<String, dynamic>);
        final accessToken = payload['access_token'] as String?;
        final updatedRefreshToken = payload['refresh_token'] as String?;
        if (accessToken != null && accessToken.isNotEmpty) {
          final expiresIn = payload['expires_in'];
          final expirySeconds = (expiresIn is num && expiresIn > 120)
              ? expiresIn.toInt() - 120
              : 3000;
          final expiry = DateTime.now().toUtc().add(Duration(seconds: expirySeconds));
          await _storeGoogleTokens(
            accessToken: accessToken,
            refreshToken: updatedRefreshToken,
            expiry: expiry,
          );
          diagnostics?.add('✅ Refreshed Google token via Supabase Edge Function');
          return _RefreshResult(token: accessToken);
        }
      } else {
        final errText = data is Map ? (data['error'] ?? data['message']) : data.toString();
        diagnostics?.add('⚠️ Edge Function request failed (${res.status}).');
        if (errText.toString().toLowerCase().contains('invalid_grant')) {
          return const _RefreshResult(
            error: 'Google Drive authorization was revoked or expired. Please sign in again.',
            needsRelogin: true,
          );
        }
      }
    } catch (e) {
      diagnostics?.add('⚠️ Edge Function refresh request failed (${e.runtimeType}).');
    }

    // Direct Google refresh. Web-type OAuth clients require the client
    // secret; without it Google rejects the refresh grant.
    if (_googleOAuthClientId.isNotEmpty) {
      try {
        final tokenClient = http.Client();
        final tokenRequest = http.Request(
          'POST',
          Uri.parse('https://oauth2.googleapis.com/token'),
        )
          ..followRedirects = false
          ..headers['Content-Type'] = 'application/x-www-form-urlencoded'
          ..bodyFields = {
            'client_id': _googleOAuthClientId,
            if (_googleOAuthClientSecret.isNotEmpty)
              'client_secret': _googleOAuthClientSecret,
            'grant_type': 'refresh_token',
            'refresh_token': refreshToken,
          };
        final http.Response response;
        try {
          final streamedResponse = await tokenClient
              .send(tokenRequest)
              .timeout(const Duration(seconds: 15));
          response = await http.Response.fromStream(streamedResponse)
              .timeout(const Duration(seconds: 15));
        } finally {
          tokenClient.close();
        }
        final body = response.body;
        if (response.statusCode == 200) {
          final payload = jsonDecode(body) as Map<String, dynamic>;
          final accessToken = payload['access_token'] as String?;
          if (accessToken != null && accessToken.isNotEmpty) {
            final expiresIn = payload['expires_in'];
            final expirySeconds = (expiresIn is num && expiresIn > 120)
                ? expiresIn.toInt() - 120
                : 3000;
            final expiry = DateTime.now().toUtc().add(Duration(seconds: expirySeconds));
            await _storeGoogleTokens(
              accessToken: accessToken,
              refreshToken: payload['refresh_token'] as String?,
              expiry: expiry,
            );
            diagnostics?.add('✅ Google Drive access token refreshed silently');
            return _RefreshResult(token: accessToken);
          }
        }
        final failure = _DriveFailure.fromResponse(response.statusCode, body);
        diagnostics?.add('⚠️ Direct Google OAuth refresh failed (${response.statusCode}).');
        if (failure.invalidGrant) {
          return const _RefreshResult(
            error: 'Google Drive authorization was revoked or expired. Please sign in again.',
            needsRelogin: true,
          );
        }
      } catch (e) {
        diagnostics?.add('⚠️ Direct Google OAuth refresh request failed (${e.runtimeType}).');
      }
    }

    return const _RefreshResult(
      error: 'Unable to refresh Google Drive token via Edge Function or direct fallback. Please sign in again.',
      needsRelogin: true,
    );
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
    // NEVER overwrite an existing stored refreshToken with a null/empty value
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
  /// Gets or creates an app-private folder inside Drive's appDataFolder.
  static Future<String> _getOrCreateBackupFolder(drive.DriveApi driveApi) async {
    final folderList = await driveApi.files.list(
      spaces: 'appDataFolder',
      q: "mimeType = 'application/vnd.google-apps.folder' and name = 'nexon_data' and trashed = false",
      $fields: 'files(id)',
      pageSize: 1,
    );
    if (folderList.files?.isNotEmpty == true) {
      return folderList.files!.first.id!;
    }
    final folder = await driveApi.files.create(
      drive.File()
        ..name = 'nexon_data'
        ..mimeType = 'application/vnd.google-apps.folder',
    );
    return folder.id!;
  }

  static Future<List<drive.File>> _listBackupFiles(
    drive.DriveApi driveApi,
    String folderId,
  ) async {
    final files = await driveApi.files.list(
      spaces: 'appDataFolder',
      q: "'$folderId' in parents and trashed = false",
      $fields: 'files(id,name,modifiedTime,size,md5Checksum,appProperties)',
      orderBy: 'modifiedTime desc',
      pageSize: 100,
    );
    return (files.files ?? []).where((file) {
      final name = file.name ?? '';
      return name == _backupFileName || name.startsWith('nexon_backup_');
    }).toList();
  }

  static Future<drive.File?> _findBackupFile(
    drive.DriveApi driveApi,
    String folderId,
  ) async {
    final files = await _listBackupFiles(driveApi, folderId);
    return files.isNotEmpty ? files.first : null;
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
    final providerApiKeys = await _collectProviderApiKeys(prefs);

    return {
      'version': 3,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'chat_sessions': serializedSessions,
      'active_session_id': prefs.getString('active_session_id_v1') ?? '',
      'provider_settings': prefs.getString('provider_settings_v1') ?? '{}',
      'custom_providers': prefs.getString('custom_providers_v1') ?? '{}',
      'provider_api_keys': providerApiKeys,
      'provider_api_key_count': providerApiKeys.length,
      'selected_provider_id': prefs.getString('selected_provider_id') ?? '',
      'search_settings': prefs.getString('search_settings_v1') ?? '{}',
      'agentic_enabled': prefs.getBool('agentic_enabled_v1') ?? true,
      'agentic_workspace': prefs.getString('agentic_workspace_v1') ?? '',
      'shell_permission': prefs.getString('shell_permission_v1') ?? 'ask',
      'custom_mcp_url': prefs.getString('custom_mcp_url_v1') ?? '',
      'user_name': prefs.getString('user_name_v1') ?? '',
      'study_mode_enabled': prefs.getBool('study_mode_enabled_v1') ?? false,
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
      } catch (_) {}
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
  // Smart Chat Merge & Restore Helper
  // ──────────────────────────────────────────────────────────────────
  static Future<int> _mergeAndRestoreChatSessions(
    SharedPreferences prefs,
    Map<String, dynamic> backupData,
    List<String> log,
  ) async {
    if (!backupData.containsKey('chat_sessions')) return 0;

    final backupSessionsRaw = backupData['chat_sessions'];
    if (backupSessionsRaw is! List) return 0;

    // Load local chat sessions
    List<Map<String, dynamic>> localSessions = [];
    final rawLocal = prefs.getString('chat_sessions_v1');
    if (rawLocal != null && rawLocal.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawLocal) as List<dynamic>;
        for (final item in decoded) {
          if (item is! Map) continue;
          try {
            localSessions.add(Map<String, dynamic>.from(item));
          } catch (_) {
            continue;
          }
        }
      } catch (_) {
        // Local sessions JSON is corrupted; proceed with empty local set.
      }
    }

    // Preferences hold only the newest sessions after the size threshold.
    // Include the app-private full copy before merging Drive so a restore
    // cannot replace newer local history with an older cloud snapshot.
    try {
      final localBackup = await sessionBackupFile();
      final backups = [
        localBackup,
        ...await _legacySessionBackupFiles(prefs),
      ];
      for (final file in backups) {
        try {
          if (file.path == localBackup.path || await file.exists()) {
            final decoded = jsonDecode(await file.readAsString());
            if (decoded is List) {
              localSessions.addAll(
                decoded.whereType<Map>().map(
                  (item) => Map<String, dynamic>.from(item),
                ),
              );
            }
          }
        } catch (_) {
          continue;
        }
      }
    } catch (_) {
      // Keep any valid preference sessions if the full local copy is damaged.
    }

    final mergedMap = <String, Map<String, dynamic>>{};
    for (final s in localSessions) {
      final id = s['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final previous = mergedMap[id];
      if (previous == null || _shouldReplaceSession(previous, s)) {
        mergedMap[id] = s;
      }
    }

    int addedFromRemote = 0;
    int updatedFromRemote = 0;
    final localCount = localSessions.length;

    for (final remoteRaw in backupSessionsRaw) {
      if (remoteRaw is! Map) continue;
      final Map<String, dynamic> remote;
      try {
        remote = Map<String, dynamic>.from(remoteRaw);
      } catch (_) {
        continue;
      }
      final id = remote['id']?.toString();
      if (id == null || id.isEmpty) continue;

      if (!mergedMap.containsKey(id)) {
        mergedMap[id] = remote;
        addedFromRemote++;
      } else {
        final local = mergedMap[id]!;
        if (_shouldReplaceSession(local, remote)) {
          mergedMap[id] = remote;
          updatedFromRemote++;
        }
      }
    }

    final mergedList = mergedMap.values.toList();

    // Sort: pinned first, then descending by updatedAt
    mergedList.sort((a, b) {
      final aPinned = a['isPinned'] == true;
      final bPinned = b['isPinned'] == true;
      if (aPinned != bPinned) return aPinned ? -1 : 1;

      final aTime = DateTime.tryParse(a['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = DateTime.tryParse(b['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    final allJson = jsonEncode(mergedList);
    final allJsonBytes = utf8.encode(allJson).length;
    const maxPrefsBytes = 1500 * 1024;

    if (allJsonBytes <= maxPrefsBytes) {
      final backupFile = await sessionBackupFile();
      final saved = await prefs.setString('chat_sessions_v1', allJson);
      if (saved) {
        try {
          if (await backupFile.exists()) await backupFile.delete();
        } catch (_) {}
        await _removeLegacySessionBackupFiles(prefs);
      } else {
        await _writeSessionBackup(backupFile, allJson);
        log.add('📦 Preferences were unavailable; kept the full chat copy locally.');
      }
    } else {
      var backupOk = false;
      try {
        final backupFile = await sessionBackupFile();
        await _writeSessionBackup(backupFile, allJson);
        backupOk = true;
        log.add(
          '📦 Session payload exceeds 1.5MB; offloaded complete set to local backup file.',
        );
      } catch (e) {
        log.add('⚠️ Failed to write local session backup: $e');
      }
      if (backupOk) {
        final saved = await prefs.setString(
          'chat_sessions_v1',
          jsonEncode(mergedList.take(20).toList()),
        );
        if (!saved) {
          log.add('📦 Full chat history is safe locally; preferences could not be updated.');
        }
        await _removeLegacySessionBackupFiles(prefs);
      } else {
        // Preserve all chats in preferences if the full local copy could not
        // be committed; never truncate first and hope the file write succeeds.
        final saved = await prefs.setString('chat_sessions_v1', allJson);
        if (!saved) {
          throw StateError('Could not persist restored chat history.');
        }
        await _removeLegacySessionBackupFiles(prefs);
      }
    }

    log.add(
      '✅ Merged $localCount local chats with ${backupSessionsRaw.length} remote chats. Result: ${mergedList.length} chats ($addedFromRemote added, $updatedFromRemote updated).',
    );
    return mergedList.length;
  }

  static bool _shouldReplaceSession(
    Map<String, dynamic> current,
    Map<String, dynamic> candidate,
  ) {
    final currentMessages = current['messages'] is List
        ? current['messages'] as List
        : const [];
    final candidateMessages = candidate['messages'] is List
        ? candidate['messages'] as List
        : const [];
    if (candidateMessages.length < currentMessages.length) return false;

    for (var i = 0; i < currentMessages.length; i++) {
      final currentMessage = jsonEncode(_canonicalJsonValue(currentMessages[i]));
      final candidateMessage = jsonEncode(_canonicalJsonValue(candidateMessages[i]));
      if (currentMessage != candidateMessage) return false;
    }

    final currentUpdated = DateTime.tryParse(
          current['updatedAt']?.toString() ?? '',
        ) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final candidateUpdated = DateTime.tryParse(
          candidate['updatedAt']?.toString() ?? '',
        ) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return candidateMessages.length > currentMessages.length ||
        (candidateMessages.length == currentMessages.length &&
            candidateUpdated.isAfter(currentUpdated));
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
    final stringValue = value is String ? value : jsonEncode(value);
    final existing = prefs.getString(prefsKey);
    if (existing != null && existing.trim().isNotEmpty && existing != '{}') {
      return;
    }
    await prefs.setString(prefsKey, stringValue);
  }

  static Future<void> _restorePrefsBool(
    SharedPreferences prefs,
    Map<String, dynamic> data,
    String backupKey,
    String prefsKey,
  ) async {
    if (data[backupKey] is! bool) return;
    if (prefs.containsKey(prefsKey)) return;
    await prefs.setBool(prefsKey, data[backupKey] as bool);
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
        final existing = await _secureStorage.read(
          key: _providerApiKeyStorageName(providerId),
        );
        if (existing != null && existing.trim().isNotEmpty) {
          continue;
        }
        await _secureStorage.write(
          key: _providerApiKeyStorageName(providerId),
          value: apiKey,
        );
        final savedKey = await _secureStorage.read(
          key: _providerApiKeyStorageName(providerId),
        );
        if (savedKey != apiKey) {
          throw StateError('Secure key storage could not be verified.');
        }
        await prefs.remove('fallback_api_key_$providerId');
      } catch (_) {
        // Do not persist provider credentials in plaintext preferences.
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

  static Future<List<int>> _encryptBackup(List<int> plaintext) async {
    final keyBytes = await _getOrCreateBackupKeyV2();
    final header = utf8.encode(_backupV3Header);
    final secretBox = await _backupCipher.encrypt(
      plaintext,
      secretKey: SecretKey(keyBytes),
      nonce: _backupCipher.newNonce(),
      aad: header,
    );
    return [
      ...header,
      ...secretBox.nonce,
      ...secretBox.mac.bytes,
      ...secretBox.cipherText,
    ];
  }

  static Future<List<int>?> _decryptBackup(List<int> ciphertext) async {
    final v3Header = utf8.encode(_backupV3Header);
    final v2Header = utf8.encode(_backupV2Header);
    final authenticatedHeader = _hasPrefix(ciphertext, v3Header)
        ? v3Header
        : (_hasPrefix(ciphertext, v2Header) ? v2Header : null);
    if (authenticatedHeader != null) {
      final payloadOffset = authenticatedHeader.length;
      final minimumLength =
          payloadOffset + _backupV2NonceBytes + _backupV2MacBytes;
      if (ciphertext.length < minimumLength) return null;

      final keyBytes = await _readBackupKeyV2();
      if (keyBytes == null) return null;
      final nonceStart = payloadOffset;
      final macStart = nonceStart + _backupV2NonceBytes;
      final encryptedStart = macStart + _backupV2MacBytes;
      final secretBox = SecretBox(
        ciphertext.sublist(encryptedStart),
        nonce: ciphertext.sublist(nonceStart, macStart),
        mac: Mac(ciphertext.sublist(macStart, encryptedStart)),
      );
      try {
        return await _backupCipher.decrypt(
          secretBox,
          secretKey: SecretKey(keyBytes),
          aad: authenticatedHeader,
        );
      } catch (_) {
        // Authentication failure means the backup was changed or the key differs.
        return null;
      }
    }

    // Compatibility path for existing V1 backups. V1 has no authentication;
    // new backups are never written in this format.
    final v1Header = utf8.encode(_backupV1Header);
    if (!_hasPrefix(ciphertext, v1Header)) return null;
    final legacyKey = await _secureStorage.read(key: _encryptionKeyStorage);
    if (legacyKey == null || legacyKey.isEmpty) return null;
    final keyBytes = utf8.encode(legacyKey);
    final keyHash = md5.convert(keyBytes).bytes;
    final iv = List<int>.generate(16, (i) => (keyHash[i] + i * 31) & 0xFF);
    final encrypted = ciphertext.sublist(v1Header.length);
    return List<int>.generate(encrypted.length, (i) {
      return encrypted[i] ^ keyBytes[i % keyBytes.length] ^ iv[i % iv.length];
    });
  }

  static bool _hasPrefix(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  static Future<List<int>?> _readBackupKeyV2() async {
    final encoded = await _secureStorage.read(key: _encryptionKeyStorageV2);
    if (encoded == null) return null;
    try {
      final keyBytes = base64Url.decode(encoded);
      return keyBytes.length == 32 ? keyBytes : null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<int>> _getOrCreateBackupKeyV2() async {
    final pending = _creatingBackupKeyV2;
    if (pending != null) return pending;

    final existing = await _readBackupKeyV2();
    if (existing != null) return existing;
    if (await _secureStorage.read(key: _encryptionKeyStorageV2) != null) {
      throw StateError('The stored backup encryption key is invalid.');
    }

    final pendingAfterRead = _creatingBackupKeyV2;
    if (pendingAfterRead != null) return pendingAfterRead;

    final creation = () async {
      final random = math.Random.secure();
      final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
      final encoded = base64UrlEncode(keyBytes);
      await _secureStorage.write(
        key: _encryptionKeyStorageV2,
        value: encoded,
      );
      final persisted = await _secureStorage.read(key: _encryptionKeyStorageV2);
      if (persisted != encoded) {
        throw StateError('Could not persist the backup encryption key securely.');
      }
      return keyBytes;
    }();
    _creatingBackupKeyV2 = creation;
    try {
      return await creation;
    } finally {
      _creatingBackupKeyV2 = null;
    }
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

