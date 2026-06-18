/// TermuxForge — Chat Screen
///
/// Agent chat interface with message bubbles, markdown rendering,
/// code blocks with "Apply" buttons, streaming text animation,
/// tool call indicators, and cost tracking per message.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:termux_forge/core/theme/app_colors.dart';
import 'package:termux_forge/presentation/widgets/agent_avatar.dart';
import 'package:termux_forge/presentation/widgets/forge_app_bar.dart';
import 'package:termux_forge/presentation/widgets/glass_card.dart';
import 'package:termux_forge/presentation/widgets/mode_selector.dart';
import 'package:termux_forge/presentation/widgets/status_badge.dart';

/// A single chat message model (local UI model).
class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.agentType = 'orchestrator',
    this.model,
    this.toolCalls = const [],
    this.fileRefs = const [],
    this.cost,
    this.isStreaming = false,
  });

  final String role; // 'user' | 'agent'
  final String content;
  final DateTime timestamp;
  final String agentType;
  final String? model;
  final List<String> toolCalls;
  final List<String> fileRefs;
  final double? cost;
  final bool isStreaming;
}

/// The agent chat screen.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  String _currentMode = 'code';
  String _selectedAgent = 'orchestrator';

  // Demo messages.
  final List<_ChatMessage> _messages = [
    _ChatMessage(
      role: 'user',
      content: 'Create a Flutter login screen with email and password fields.',
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
    _ChatMessage(
      role: 'agent',
      content:
          "I'll create a beautiful login screen for you. Let me set up the "
          "file structure first.\n\n"
          "```dart\n"
          "class LoginScreen extends StatefulWidget {\n"
          "  const LoginScreen({super.key});\n\n"
          "  @override\n"
          "  State<LoginScreen> createState() => _LoginScreenState();\n"
          "}\n"
          "```\n\n"
          "I've created the login screen with:\n"
          "- Email text field with validation\n"
          "- Password field with visibility toggle\n"
          "- Animated submit button\n"
          "- Error handling",
      timestamp: DateTime.now().subtract(const Duration(minutes: 4)),
      agentType: 'coder',
      model: 'Claude 4 Sonnet',
      toolCalls: ['write_file', 'read_file'],
      fileRefs: ['lib/screens/login_screen.dart'],
      cost: 0.0023,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_ChatMessage(
        role: 'user',
        content: text,
        timestamp: DateTime.now(),
      ));
      _controller.clear();
    });
    // Scroll to bottom.
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ForgeAppBar(
        title: 'Chat',
        currentMode: _currentMode,
        currentModel: 'Claude 4 Sonnet',
        showBackButton: true,
        onModeTap: () => _showModeSelector(context),
      ),
      body: Column(
        children: [
          // ── Agent selector + mode bar ──
          _buildHeaderBar(context),

          // ── Message list ──
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _MessageBubble(
                      message: _messages[i],
                      isLast: i == _messages.length - 1,
                    ).animate().fadeIn(
                      delay: Duration(milliseconds: i * 50),
                      duration: 250.ms,
                    ),
                  ),
          ),

          // ── Input bar ──
          _buildInputBar(context),
        ],
      ),
    );
  }

  Widget _buildHeaderBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          // Agent selector.
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _showAgentSelector(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AgentAvatar(
                  agentType: _selectedAgent,
                  size: AvatarSize.small,
                ),
                const SizedBox(width: 8),
                Text(
                  _selectedAgent.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Icon(Icons.arrow_drop_down_rounded, size: 18),
              ],
            ),
          ),
          const Spacer(),
          // Battle mode toggle.
          IconButton(
            icon: const Icon(Icons.compare_arrows_rounded, size: 18),
            onPressed: () {},
            tooltip: 'Battle Mode',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppColors.cardGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 48,
              color: AppColors.accentBlue,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Start a conversation',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Ask the agent to write code, debug, or explain concepts.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 12,
        bottom: MediaQuery.paddingOf(context).bottom + 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Attach button.
          IconButton(
            icon: const Icon(Icons.attach_file_rounded, size: 20),
            onPressed: () {},
            tooltip: 'Attach file',
          ),
          // Text field.
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: 'Message ${_selectedAgent}...',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button.
          IconButton.filled(
            onPressed: _sendMessage,
            icon: const Icon(Icons.send_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  void _showModeSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SizedBox(
        height: 420,
        child: ModeSelector(
          currentMode: _currentMode,
          scrollDirection: Axis.vertical,
          onModeChanged: (m) {
            setState(() => _currentMode = m);
            Navigator.pop(ctx);
          },
        ),
      ),
    );
  }

  void _showAgentSelector(BuildContext context) {
    final agents = [
      'orchestrator',
      'coder',
      'architect',
      'debugger',
      'reviewer',
      'devops',
      'researcher',
      'tester',
      'documenter',
      'security',
    ];

    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.all(8),
        itemCount: agents.length,
        itemBuilder: (_, i) {
          final agent = agents[i];
          return ListTile(
            leading: AgentAvatar(agentType: agent, size: AvatarSize.small),
            title: Text(agent[0].toUpperCase() + agent.substring(1)),
            selected: agent == _selectedAgent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            onTap: () {
              setState(() => _selectedAgent = agent);
              Navigator.pop(ctx);
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────
//  Message Bubble
// ─────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, this.isLast = false});

  final _ChatMessage message;
  final bool isLast;

  bool get _isUser => message.role == 'user';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            _isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!_isUser) ...[
            AgentAvatar(
              agentType: message.agentType,
              size: AvatarSize.small,
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Agent name + model badge.
                if (!_isUser)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message.agentType[0].toUpperCase() +
                              message.agentType.substring(1),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.agentColor(message.agentType),
                          ),
                        ),
                        if (message.model != null) ...[
                          const SizedBox(width: 8),
                          StatusBadge(
                            label: message.model!,
                            color: AppColors.accentPurple,
                            size: BadgeSize.small,
                          ),
                        ],
                      ],
                    ),
                  ),

                // Message body.
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.75,
                  ),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _isUser
                        ? AppColors.accentBlue.withValues(alpha: 0.15)
                        : AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(_isUser ? 16 : 4),
                      bottomRight: Radius.circular(_isUser ? 4 : 16),
                    ),
                    border: Border.all(
                      color: _isUser
                          ? AppColors.accentBlue.withValues(alpha: 0.2)
                          : AppColors.borderSubtle,
                      width: 0.5,
                    ),
                  ),
                  child: MarkdownBody(
                    data: message.content,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(
                      Theme.of(context),
                    ).copyWith(
                      p: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                      code: GoogleFonts.jetBrainsMono(
                        fontSize: 13,
                        color: AppColors.accentBlue,
                        backgroundColor: AppColors.backgroundPrimary,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: AppColors.backgroundPrimary,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      codeblockPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ),

                // ── Tool calls ──
                if (message.toolCalls.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    children: message.toolCalls.map((tool) {
                      return StatusBadge(
                        label: tool,
                        color: AppColors.accentTeal,
                        size: BadgeSize.small,
                        icon: Icons.build_rounded,
                      );
                    }).toList(),
                  ),
                ],

                // ── File references ──
                if (message.fileRefs.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    children: message.fileRefs.map((file) {
                      return ActionChip(
                        avatar: const Icon(
                          Icons.insert_drive_file_outlined,
                          size: 14,
                        ),
                        label: Text(
                          file.split('/').last,
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: () {
                          // TODO: Open file in editor.
                        },
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ],

                // ── Cost ──
                if (message.cost != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '\$${message.cost!.toStringAsFixed(4)}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
