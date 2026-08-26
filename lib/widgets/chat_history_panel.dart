// Extracted from main.dart lines 7887-8218
// Extracted on: 2026-08-26T18:20:45.736142

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexon/main.dart';

class ChatHistoryPanel extends StatelessWidget {
  const ChatHistoryPanel({
    required this.sessions,
    required this.activeSessionId,
    required this.onSessionTap,
    required this.onSessionDelete,
    required this.onSessionRename,
    required this.onSessionPinToggle,
    required this.onNewChat,
    required this.visibleLimit,
    required this.isLoadingMore,
    required this.onLoadMore,
    super.key,
  });

  final List<ChatSession> sessions;
  final String? activeSessionId;
  final ValueChanged<String> onSessionTap;
  final ValueChanged<String> onSessionDelete;
  final void Function(String sessionId, String newTitle) onSessionRename;
  final ValueChanged<String> onSessionPinToggle;
  final VoidCallback onNewChat;
  final int visibleLimit;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    // Sort pinned chats to the top
    final sortedSessions = List<ChatSession>.from(sessions)
      ..sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return 0; // Maintain original relative order
      });

    final displayedSessions = sortedSessions.take(visibleLimit).toList();

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final sevenDaysStart = todayStart.subtract(const Duration(days: 7));

    String getBucket(DateTime date) {
      if (date.isAfter(todayStart) || date.isAtSameMomentAs(todayStart)) {
        return 'Today';
      } else if (date.isAfter(yesterdayStart) ||
          date.isAtSameMomentAs(yesterdayStart)) {
        return 'Yesterday';
      } else if (date.isAfter(sevenDaysStart) ||
          date.isAtSameMomentAs(sevenDaysStart)) {
        return 'Previous 7 Days';
      } else {
        return 'Older';
      }
    }

    final buckets = ['Today', 'Yesterday', 'Previous 7 Days', 'Older'];
    final Map<String, List<ChatSession>> grouped = {
      for (final b in buckets) b: <ChatSession>[],
    };

    for (final session in displayedSessions) {
      final b = getBucket(session.updatedAt);
      grouped[b]!.add(session);
    }

    final List<Widget> listItems = [];
    for (final bucket in buckets) {
      final items = grouped[bucket]!;
      if (items.isEmpty) continue;

      listItems.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Text(
            bucket.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: Color(0xFF8C7A6B),
            ),
          ),
        ),
      );

      for (final session in items) {
        final selected = session.id == activeSessionId;
        final messageCount = session.messages.length;
        listItems.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 4.0),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: selected
                    ? const Color(0xFFFFF6E5).withValues(alpha: 0.95)
                    : const Color(0xFFFFFDF8).withValues(alpha: 0.8),
                border: Border.all(
                  color: selected
                      ? const Color(0xFFD8B98D)
                      : const Color(0xFFE5DDD3),
                ),
              ),
              child: ListTile(
                dense: true,
                selected: selected,
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (session.isPinned)
                      const Padding(
                        padding: EdgeInsets.only(right: 4.0),
                        child: Icon(
                          Icons.push_pin,
                          size: 12,
                          color: Color(0xFF7B4E2E),
                        ),
                      ),
                    const Icon(
                      Icons.chat_bubble_outline,
                      size: 18,
                      color: Color(0xFF5C3D26),
                    ),
                  ],
                ),
                title: Text(
                  session.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: const Color(0xFF33291F),
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  '$messageCount message${messageCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Color(0xFF6C5946),
                    fontSize: 11,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  color: const Color(0xFF8C7A6B),
                  onPressed: () => onSessionDelete(session.id),
                ),
                onTap: () => onSessionTap(session.id),
                onLongPress: () {
                  _showOptionsSheet(context, session);
                },
              ),
            ),
          ),
        );
      }
    }

    listItems.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 6.0),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            side: const BorderSide(color: Color(0xFFD8B98D), width: 1.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            backgroundColor: const Color(0xFFFFF8EA),
          ),
          onPressed: isLoadingMore ? null : onLoadMore,
          icon: isLoadingMore
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF7B4E2E),
                  ),
                )
              : const Icon(Icons.history, size: 18, color: Color(0xFF7B4E2E)),
          label: Text(
            isLoadingMore
                ? 'Loading…'
                : 'Load earlier chats',
            style: const TextStyle(
              color: Color(0xFF7B4E2E),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );

    return Container(
      color: const Color(0xFFEFE6D6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(
              children: [
                const AppMark(),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Nexon',
                    style: GoogleFonts.notoSerif(
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF2D241C),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'New chat',
                  onPressed: onNewChat,
                  icon: const Icon(Icons.add_comment_outlined),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFFDCCBB8), height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 18),
              children: listItems,
            ),
          ),
        ],
      ),
    );
  }

  void _showOptionsSheet(BuildContext context, ChatSession session) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFFFFBF2),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  session.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D241C),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(color: Color(0xFFE7D8C4), height: 1),
              ListTile(
                leading: Icon(
                  session.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                  color: const Color(0xFF7B4E2E),
                ),
                title: Text(
                  session.isPinned ? 'Unpin chat' : 'Pin chat to top',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onSessionPinToggle(session.id);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.edit_outlined,
                  color: Color(0xFF7B4E2E),
                ),
                title: const Text(
                  'Rename chat',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  _showRenameDialog(context, session);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showRenameDialog(BuildContext context, ChatSession session) {
    final controller = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFBF2),
        title: const Text(
          'Rename Chat',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Chat Title'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                onSessionRename(session.id, newTitle);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }
}
