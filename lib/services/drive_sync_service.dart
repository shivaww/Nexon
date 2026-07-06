import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class GoogleAuthClient extends http.BaseClient {
  final String _token;
  final http.Client _inner = http.Client();

  GoogleAuthClient(this._token);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }
}

class DriveSyncService {
  static Future<void> syncToDrive() async {
    final prefs = await SharedPreferences.getInstance();
    final backupEnabled = prefs.getBool('google_drive_backup_enabled') ?? false;
    
    if (!backupEnabled) {
      print('Drive backup is disabled by user.');
      return;
    }

    final session = Supabase.instance.client.auth.currentSession;
    final providerToken = session?.providerToken;

    if (providerToken == null) {
      print('No Google Provider Token available. Cannot sync to Drive.');
      return;
    }

    try {
      final authenticateClient = GoogleAuthClient(providerToken);
      final driveApi = drive.DriveApi(authenticateClient);

      // We will store all chats, keys, and memory in a single JSON backup for simplicity
      final backupData = {
        'chat_sessions': prefs.getString('chat_sessions_v1') ?? '[]',
        'provider_settings': prefs.getString('provider_settings_v1') ?? '{}',
      };

      // Also grab the AI Memory file if it exists
      final docDir = await getApplicationDocumentsDirectory();
      final memoryFile = File('${docDir.path}/nexon_memory.json');
      if (await memoryFile.exists()) {
        backupData['ai_memory'] = await memoryFile.readAsString();
      }

      final jsonBackup = jsonEncode(backupData);
      final bytes = utf8.encode(jsonBackup);
      final media = drive.Media(Stream.value(bytes), bytes.length);

      // Search for existing backup in appDataFolder
      final fileList = await driveApi.files.list(
        spaces: 'appDataFolder',
        q: "name = 'nexon_backup.json'",
      );

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        // Update existing file
        final fileId = fileList.files!.first.id!;
        await driveApi.files.update(
          drive.File(),
          fileId,
          uploadMedia: media,
        );
        print('Successfully updated nexon_backup.json in Google Drive appDataFolder.');
      } else {
        // Create new file
        final driveFile = drive.File()
          ..name = 'nexon_backup.json'
          ..parents = ['appDataFolder'];
        await driveApi.files.create(
          driveFile,
          uploadMedia: media,
        );
        print('Successfully created nexon_backup.json in Google Drive appDataFolder.');
      }
    } catch (e) {
      print('Drive sync failed: $e');
    }
  }
}
