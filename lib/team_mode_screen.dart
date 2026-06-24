import 'package:flutter/material.dart';
import 'team_mode_models.dart';
import 'team_session_manager.dart';

class TeamModeScreen extends StatefulWidget {
  const TeamModeScreen({super.key});

  @override
  State<TeamModeScreen> createState() => _TeamModeScreenState();
}

class _TeamModeScreenState extends State<TeamModeScreen> {
  final TeamSessionManager _manager = TeamSessionManager();
  List<TeamSessionState> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    final sessions = await _manager.loadAllSessions();
    setState(() {
      _sessions = sessions;
      _isLoading = false;
    });
  }

  Future<void> _startNewSession() async {
    final TextEditingController controller = TextEditingController();
    final task = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New AI Team Task'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'e.g. Build a login screen with biometric auth'),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Start Team')),
        ],
      ),
    );

    if (task != null && task.isNotEmpty) {
      final newState = TeamSessionState.create(task);
      await _manager.saveSessionState(newState);
      await _loadSessions();
      // TODO: Navigate to session detail / execution view
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Team Orchestration'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _startNewSession),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.group_work, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('No team sessions yet.', style: TextStyle(fontSize: 18)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _startNewSession,
                        icon: const Icon(Icons.add),
                        label: const Text('Start New Team Task'),
                      )
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final session = _sessions[index];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.work)),
                      title: Text(session.taskDescription, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('Phase: ${session.currentPhase.name.toUpperCase()}'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        // TODO: Open session detail screen
                      },
                    );
                  },
                ),
    );
  }
}
