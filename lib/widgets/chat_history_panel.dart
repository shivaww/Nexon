// Extracted from main.dart lines 7887-8218
// Extracted on: 2026-08-26T18:20:45.736142

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexon/main.dart';

class _ChatHistoryBody extends StatelessWidget {
  const _ChatHistoryBody({
    required this.query,
    required this.searchController,
    required this.onQueryChanged,
    required this.modesOf,
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
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final _ChatModes Function(ChatSession) modesOf;

  @override
  Widget build(BuildContext context) {
    // Sort pinned chats to the top
    final q = query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? sessions
        : sessions.where((s) => _sessionMatches(s, q)).toList();
    // Explicit, stable order: pinned first, then blank (new) chats, then
    // everything else in its existing order. List.sort is not stable, so a
    // comparator returning 0 could shuffle a new chat into the middle.
    final pinnedSessions = filtered.where((s) => s.isPinned).toList();
    final unpinnedSessions = filtered.where((s) => !s.isPinned).toList();
    final blankSessions =
        unpinnedSessions.where((s) => s.messages.isEmpty).toList();
    final usedSessions =
        unpinnedSessions.where((s) => s.messages.isNotEmpty).toList();
    final sortedSessions = <ChatSession>[
      ...pinnedSessions,
      ...blankSessions,
      ...usedSessions,
    ];

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
      // Blank chats always show under Today so a new chat is at the top.
      final b = session.messages.isEmpty
          ? 'Today'
          : getBucket(session.updatedAt);
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
        final modes = modesOf(session);
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
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        session.title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: const Color(0xFF33291F),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (modes.study)
                      _modeBadge(Icons.school_outlined, 'Study mode'),
                    if (modes.research)
                      _modeBadge(Icons.travel_explore_rounded, 'Deep research'),
                    if (modes.agentic)
                      _modeBadge(Icons.terminal_rounded, 'Agentic'),
                  ],
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

    if (q.isNotEmpty && displayedSessions.isEmpty) {
      listItems.add(
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 24, 14, 8),
          child: Text(
            'No chats match your search',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF8C7A6B), fontSize: 13),
          ),
        ),
      );
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
            isLoadingMore ? 'Loading…' : 'Load earlier chats',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: TextField(
              controller: searchController,
              onChanged: onQueryChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 13, color: Color(0xFF33291F)),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search chats',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF8C7A6B),
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: Color(0xFF8C7A6B),
                ),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16),
                        color: const Color(0xFF8C7A6B),
                        onPressed: () {
                          searchController.clear();
                          onQueryChanged('');
                        },
                      ),
                filled: true,
                fillColor: const Color(0xFFFFFDF8),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5DDD3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5DDD3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFD8B98D)),
                ),
              ),
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

class _ChatModes {
  const _ChatModes({
    this.study = false,
    this.research = false,
    this.agentic = false,
  });
  final bool study;
  final bool research;
  final bool agentic;
}

Widget _modeBadge(IconData icon, String tip) => Padding(
  padding: const EdgeInsets.only(left: 6),
  child: Tooltip(
    message: tip,
    child: Icon(icon, size: 13, color: const Color(0xFF9A8672)),
  ),
);

bool _hasText(String t, String q) =>
    (t.length > 800 ? t.substring(0, 800) : t).toLowerCase().contains(q);

bool _sessionMatches(ChatSession s, String q) {
  if (s.title.toLowerCase().contains(q)) return true;
  final msgs = s.messages;
  if (msgs.isEmpty) return false;
  for (final m in msgs) {
    if (m.role == MessageRole.user) {
      if (_hasText(m.text, q)) return true;
      break;
    }
  }
  return _hasText(msgs.last.text, q);
}

class ChatHistoryPanel extends StatefulWidget {
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
  State<ChatHistoryPanel> createState() => _ChatHistoryPanelState();
}

class _ChatHistoryPanelState extends State<ChatHistoryPanel> {
  final TextEditingController _search = TextEditingController();
  final Map<String, (int, bool, bool)> _modeCache = {};
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  _ChatModes _modesOf(ChatSession s) {
    final n = s.messages.length;
    final hit = _modeCache[s.id];
    if (hit != null && hit.$1 == n) {
      return _ChatModes(
        study: s.studyModeEnabled,
        research: hit.$2,
        agentic: hit.$3,
      );
    }
    var research = false;
    var agentic = false;
    for (final m in s.messages) {
      if (m.role == MessageRole.user || m.role == MessageRole.system) continue;
      final t = m.text;
      if (!research &&
          (t.contains('"research_plan"') || t.contains('"research_state"'))) {
        research = true;
      }
      if (!agentic && t.contains('```') && findNativeToolFence(t) != null) {
        agentic = true;
      }
      if (research && agentic) break;
    }
    _modeCache[s.id] = (n, research, agentic);
    return _ChatModes(
      study: s.studyModeEnabled,
      research: research,
      agentic: agentic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return _ChatHistoryBody(
      sessions: w.sessions,
      activeSessionId: w.activeSessionId,
      onSessionTap: w.onSessionTap,
      onSessionDelete: w.onSessionDelete,
      onSessionRename: w.onSessionRename,
      onSessionPinToggle: w.onSessionPinToggle,
      onNewChat: w.onNewChat,
      visibleLimit: w.visibleLimit,
      isLoadingMore: w.isLoadingMore,
      onLoadMore: w.onLoadMore,
      query: _query,
      searchController: _search,
      onQueryChanged: (v) => setState(() => _query = v),
      modesOf: _modesOf,
    );
  }
}
