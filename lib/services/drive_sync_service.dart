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
  static Future<bool> syncToDrive(List<dynamic> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final backupEnabled = prefs.getBool('google_drive_backup_enabled') ?? false;
    
    if (!backupEnabled) {
      print('Drive backup is disabled by user.');
      return false;
    }

    final session = Supabase.instance.client.auth.currentSession;
    var providerToken = session?.providerToken;
    if (providerToken != null) {
      await prefs.setString('google_provider_token', providerToken);
    } else {
      providerToken = prefs.getString('google_provider_token');
    }

    if (providerToken == null || providerToken.isEmpty) {
      print('No Google Provider Token available. Cannot sync to Drive.');
      return false;
    }

    try {
      final authenticateClient = GoogleAuthClient(providerToken);
      final driveApi = drive.DriveApi(authenticateClient);

      // We will store all chats, keys, memory, and artifacts in a single JSON backup for simplicity
      final backupData = {
        'chat_sessions': jsonEncode(sessions),
        'provider_settings': prefs.getString('provider_settings_v1') ?? '{}',
      };

      // Also grab the AI Memory file if it exists
      final docDir = await getApplicationDocumentsDirectory();
      final memoryFile = File('${docDir.path}/nexon_memory.json');
      if (await memoryFile.exists()) {
        backupData['ai_memory'] = await memoryFile.readAsString();
      }

      // Grab all artifacts, SVGs, and graphs from the brain directory
      final Map<String, String> artifactsMap = {};
      final brainDir = Directory('${docDir.path}/brain');
      if (await brainDir.exists()) {
        final entities = await brainDir.list(recursive: true).toList();
        for (final entity in entities) {
          if (entity is File) {
            final fileName = entity.path.split('/').last;
            // Only back up files under 2MB to prevent OOM
            if (await entity.length() < 2 * 1024 * 1024) {
              try {
                // If it's a text file (md, svg, json), read it as string. Otherwise base64 encode it.
                if (fileName.endsWith('.md') || fileName.endsWith('.svg') || fileName.endsWith('.json') || fileName.endsWith('.txt')) {
                  artifactsMap[fileName] = await entity.readAsString();
                } else {
                  artifactsMap[fileName] = base64Encode(await entity.readAsBytes());
                }
              } catch (e) {
                print('Could not read artifact $fileName: $e');
              }
            }
          }
        }
      }
      backupData['artifacts'] = jsonEncode(artifactsMap);

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
      return true;
    } catch (e) {
      if (e.toString().contains('401') || e.toString().contains('Unauthorized')) {
        print('Google Drive backup failed: Token expired (401). Please re-login to Supabase to refresh the token.');
      } else {
        print('Drive sync failed: $e');
      }
      return false;
    }
  }

  static Future<bool> restoreFromDrive() async {
    final prefs = await SharedPreferences.getInstance();
    final session = Supabase.instance.client.auth.currentSession;
    var providerToken = session?.providerToken;
    if (providerToken != null) {
      await prefs.setString('google_provider_token', providerToken);
    } else {
      providerToken = prefs.getString('google_provider_token');
    }

    if (providerToken == null || providerToken.isEmpty) {
      print('No Google Provider Token available. Cannot restore from Drive.');
      return false;
    }

    try {
      final authenticateClient = GoogleAuthClient(providerToken);
      final driveApi = drive.DriveApi(authenticateClient);

      final fileList = await driveApi.files.list(
        spaces: 'appDataFolder',
        q: "name = 'nexon_backup.json'",
      );

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        final fileId = fileList.files!.first.id!;
        final response = await driveApi.files.get(
          fileId,
          downloadOptions: drive.DownloadOptions.fullMedia,
        ) as drive.Media;
        
        final List<int> dataStore = [];
        await for (var data in response.stream) {
          dataStore.addAll(data);
        }
        final jsonBackup = utf8.decode(dataStore);
        final backupData = jsonDecode(jsonBackup) as Map<String, dynamic>;

        if (backupData.containsKey('chat_sessions')) {
           final chatData = backupData['chat_sessions'];
           if (chatData is String) {
              await prefs.setString('chat_sessions_v1', chatData);
           } else {
              await prefs.setString('chat_sessions_v1', jsonEncode(chatData));
           }
        }
        if (backupData.containsKey('provider_settings')) {
           final provData = backupData['provider_settings'];
           if (provData is String) {
              await prefs.setString('provider_settings_v1', provData);
           } else {
              await prefs.setString('provider_settings_v1', jsonEncode(provData));
           }
        }
        
        // Restore AI Memory
        final docDir = await getApplicationDocumentsDirectory();
        if (backupData.containsKey('ai_memory')) {
           final memoryFile = File('${docDir.path}/nexon_memory.json');
           await memoryFile.writeAsString(backupData['ai_memory'].toString());
        }

        // Restore artifacts
        if (backupData.containsKey('artifacts')) {
           final artifactsData = backupData['artifacts'];
           Map<String, dynamic> artifactsMap = {};
           if (artifactsData is String) {
              artifactsMap = jsonDecode(artifactsData);
           } else if (artifactsData is Map) {
              artifactsMap = Map<String, dynamic>.from(artifactsData);
           }
           final brainDir = Directory('${docDir.path}/brain');
           if (!await brainDir.exists()) {
             await brainDir.create(recursive: true);
           }
           for (final entry in artifactsMap.entries) {
              final fileName = entry.key;
              final content = entry.value.toString();
              final file = File('${brainDir.path}/$fileName');
              if (fileName.endsWith('.md') || fileName.endsWith('.svg') || fileName.endsWith('.json') || fileName.endsWith('.txt')) {
                await file.writeAsString(content);
              } else {
                await file.writeAsBytes(base64Decode(content));
              }
           }
        }

        print('Successfully restored backup from Google Drive.');
        return true;
      } else {
        print('No backup found on Google Drive.');
      }
    } catch (e) {
      print('Drive restore failed: $e');
    }
    return false;
  }
}
