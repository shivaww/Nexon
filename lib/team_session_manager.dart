import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'team_mode_models.dart';

class TeamSessionManager {
  static final TeamSessionManager _instance = TeamSessionManager._internal();
  factory TeamSessionManager() => _instance;
  TeamSessionManager._internal();

  Future<Directory> _getSessionsDirectory() async {
    final docDir = await getApplicationDocumentsDirectory();
    final sessionsDir = Directory('${docDir.path}/ai_team_sessions');
    if (!await sessionsDir.exists()) {
      await sessionsDir.create(recursive: true);
    }
    return sessionsDir;
  }

  Future<void> saveSessionState(TeamSessionState state) async {
    final sessionsDir = await _getSessionsDirectory();
    final sessionDir = Directory('${sessionsDir.path}/${state.sessionId}');
    if (!await sessionDir.exists()) {
      await sessionDir.create(recursive: true);
    }
    final file = File('${sessionDir.path}/session_state.json');
    await file.writeAsString(jsonEncode(state.toJson()));
  }

  Future<void> saveManifest(SessionManifest manifest) async {
    final sessionsDir = await _getSessionsDirectory();
    final sessionDir = Directory('${sessionsDir.path}/${manifest.sessionId}');
    if (!await sessionDir.exists()) {
      await sessionDir.create(recursive: true);
    }
    final file = File('${sessionDir.path}/manifest.json');
    await file.writeAsString(jsonEncode(manifest.toJson()));
  }

  Future<TeamSessionState?> loadSessionState(String sessionId) async {
    try {
      final sessionsDir = await _getSessionsDirectory();
      final file = File('${sessionsDir.path}/$sessionId/session_state.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        return TeamSessionState.fromJson(jsonDecode(content));
      }
    } catch (e) {
      print('Error loading session state: $e');
    }
    return null;
  }

  Future<List<TeamSessionState>> loadAllSessions() async {
    final sessions = <TeamSessionState>[];
    try {
      final sessionsDir = await _getSessionsDirectory();
      final dirs = sessionsDir.listSync().whereType<Directory>();
      for (var dir in dirs) {
        final file = File('${dir.path}/session_state.json');
        if (await file.exists()) {
          final content = await file.readAsString();
          sessions.add(TeamSessionState.fromJson(jsonDecode(content)));
        }
      }
      sessions.sort((a, b) => b.lastCheckpoint.compareTo(a.lastCheckpoint));
    } catch (e) {
      print('Error loading sessions: $e');
    }
    return sessions;
  }
}
