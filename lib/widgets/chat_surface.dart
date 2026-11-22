// Extracted from main.dart lines 8220-8552
// Extracted on: 2026-08-26T18:20:45.734628

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexon/widgets/liquid_glass_widgets.dart';
import 'package:nexon/main.dart';

class ChatSurface extends StatefulWidget {
  const ChatSurface({
    required this.provider,
    required this.settings,
    required this.model,
    required this.messages,
    required this.sessionId,
    required this.messageController,
    required this.scrollController,
    required this.isSending,
    required this.toolStatus,
    this.activeTodos = const [],
    this.todoListVisible = false,
    this.onCloseTodoList,
    this.agenticEnabled = false,
    this.onToggleTodoList,
    required this.onOpenProvider,
    required this.onOpenModel,
    required this.onSend,
    required this.onPlusPressed,
    required this.attachedImages,
    required this.onRemoveImage,
    required this.attachedFiles,
    required this.onRemoveFile,
    required this.onEditUserMessage,
    required this.isEditing,
    required this.onCancelEdit,
    required this.agenticWorkspace,
    required this.deepResearchEnabled,
    required this.onStartResearch,
    required this.fileName,
    this.branches,
    this.activeBranchIndex,
    this.onBranchChanged,
    this.onStop,
    this.onOpenSource,
    this.onOpenLiveVoice,
    this.activeFeaturePills = const [],
    this.studyModeEnabled = false,
    this.showJumpToBottom = false,
    this.onJumpToBottom,
    this.onSuggestionSelected,
    this.onRegenerateMessage,
    this.composerFocusNode,
    super.key,
  });

  final ProviderDefinition provider;
  final ProviderSettings settings;
  final String model;
  final List<ChatMessage> messages;
  final String? sessionId;
  final TextEditingController messageController;
  final ScrollController scrollController;
  final bool isSending;
  final String toolStatus;
  final List<TodoItem> activeTodos;
  final bool todoListVisible;
  final VoidCallback? onCloseTodoList;
  final bool agenticEnabled;
  final VoidCallback? onToggleTodoList;
  final String fileName;
  final VoidCallback onOpenProvider;
  final VoidCallback onOpenModel;
  final VoidCallback onSend;
  final VoidCallback onPlusPressed;
  final VoidCallback? onOpenLiveVoice;
  final List<String> attachedImages;
  final ValueChanged<int> onRemoveImage;
  final List<AttachedFile> attachedFiles;
  final ValueChanged<int> onRemoveFile;
  final ValueChanged<int> onEditUserMessage;
  final bool isEditing;
  final VoidCallback onCancelEdit;
  final String agenticWorkspace;
  final bool deepResearchEnabled;
  final void Function(int, [Map<String, dynamic>? editedStateMap])
  onStartResearch;
  final VoidCallback? onStop;
  final void Function(String file, int page)? onOpenSource;
  final List<List<ChatMessage>>? branches;
  final int? activeBranchIndex;
  final ValueChanged<int>? onBranchChanged;
  final List<Widget> activeFeaturePills;
  final bool studyModeEnabled;
  final bool showJumpToBottom;
  final VoidCallback? onJumpToBottom;
  final ValueChanged<String>? onSuggestionSelected;
  final ValueChanged<int>? onRegenerateMessage;
  final FocusNode? composerFocusNode;

  @override
  State<ChatSurface> createState() => _ChatSurfaceState();
}

class _ChatSurfaceState extends State<ChatSurface> {
  Timer? _entryAnimationTimer;
  int? _entryAnimationIndex;

  ProviderDefinition get provider => widget.provider;
  ProviderSettings get settings => widget.settings;
  String get model => widget.model;
  List<ChatMessage> get messages => widget.messages;
  String? get sessionId => widget.sessionId;
  TextEditingController get messageController => widget.messageController;
  ScrollController get scrollController => widget.scrollController;
  bool get isSending => widget.isSending;
  String get toolStatus => widget.toolStatus;
  List<TodoItem> get activeTodos => widget.activeTodos;
  bool get todoListVisible => widget.todoListVisible;
  VoidCallback? get onCloseTodoList => widget.onCloseTodoList;
  bool get agenticEnabled => widget.agenticEnabled;
  VoidCallback? get onToggleTodoList => widget.onToggleTodoList;
  String get fileName => widget.fileName;
  VoidCallback get onOpenProvider => widget.onOpenProvider;
  VoidCallback get onOpenModel => widget.onOpenModel;
  VoidCallback get onSend => widget.onSend;
  VoidCallback get onPlusPressed => widget.onPlusPressed;
  VoidCallback? get onOpenLiveVoice => widget.onOpenLiveVoice;
  List<String> get attachedImages => widget.attachedImages;
  ValueChanged<int> get onRemoveImage => widget.onRemoveImage;
  List<AttachedFile> get attachedFiles => widget.attachedFiles;
  ValueChanged<int> get onRemoveFile => widget.onRemoveFile;
  ValueChanged<int> get onEditUserMessage => widget.onEditUserMessage;
  bool get isEditing => widget.isEditing;
  VoidCallback get onCancelEdit => widget.onCancelEdit;
  String get agenticWorkspace => widget.agenticWorkspace;
  bool get deepResearchEnabled => widget.deepResearchEnabled;
  void Function(int, [Map<String, dynamic>? editedStateMap])
  get onStartResearch => widget.onStartResearch;
  VoidCallback? get onStop => widget.onStop;
  void Function(String file, int page)? get onOpenSource => widget.onOpenSource;
  List<List<ChatMessage>>? get branches => widget.branches;
  int? get activeBranchIndex => widget.activeBranchIndex;
  ValueChanged<int>? get onBranchChanged => widget.onBranchChanged;
  List<Widget> get activeFeaturePills => widget.activeFeaturePills;
  bool get studyModeEnabled => widget.studyModeEnabled;
  bool get showJumpToBottom => widget.showJumpToBottom;
  VoidCallback? get onJumpToBottom => widget.onJumpToBottom;
  ValueChanged<String>? get onSuggestionSelected => widget.onSuggestionSelected;
  ValueChanged<int>? get onRegenerateMessage => widget.onRegenerateMessage;
  FocusNode? get composerFocusNode => widget.composerFocusNode;

  @override
  void didUpdateWidget(covariant ChatSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (sessionId != oldWidget.sessionId ||
        activeBranchIndex != oldWidget.activeBranchIndex) {
      _entryAnimationTimer?.cancel();
      _entryAnimationIndex = null;
      return;
    }
    if (messages.length <= oldWidget.messages.length) return;

    _entryAnimationIndex = _lastVisibleIndex(messages);
    _entryAnimationTimer?.cancel();
    _entryAnimationTimer = Timer(const Duration(milliseconds: 360), () {
      if (mounted) setState(() => _entryAnimationIndex = null);
    });
  }

  @override
  void dispose() {
    _entryAnimationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Everything after the last user message belongs to the in-flight turn.
    // The Thought Process block uses this to stay open across the whole tool
    // loop, instead of collapsing the moment a result message is appended.
    int lastUserIndex = -1;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == MessageRole.user) {
        lastUserIndex = i;
        break;
      }
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFBF6EC), Color(0xFFF5EFE4), Color(0xFFEFE5D5)],
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(18, 84, 18, 20),
                    itemCount: messages.length + (isSending ? 1 : 0),
                    itemBuilder: (context, int index) {
                      if (index == messages.length) {
                        // No generic "Thinking" placeholder — the assistant bubble's
                        // own StreamingCursor already signals that a reply is being
                        // generated. This row now appears only when there is real
                        // live tool progress worth reporting (e.g. a search running).
                        if (toolStatus.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF7B4E2E),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  toolStatus,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFF6C5946),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      if (_isPairedResult(messages, index)) {
                        return const SizedBox.shrink();
                      }
                      AvatarAnimationState state = AvatarAnimationState.idle;
                      if (isSending && index == messages.length - 1) {
                        final msg = messages[index];
                        final nativeTool = detectNativeToolCall(msg.text);
                        if (nativeTool == 'web_search' ||
                            nativeTool == 'search_web') {
                          state = AvatarAnimationState.searching;
                        } else if (nativeTool != null) {
                          state = AvatarAnimationState.mcp;
                        } else if ((msg.reasoning?.isNotEmpty ?? false) &&
                            msg.text.isEmpty) {
                          state = AvatarAnimationState.reasoning;
                        } else {
                          state = AvatarAnimationState.typing;
                        }
                      }
                      final isUser = messages[index].role == MessageRole.user;
                      // One assistant turn = one run of consecutive non-user
                      // messages. Earlier rounds fold their thinking and quiet
                      // tool rows into the turn's last visible bubble, keeping
                      // one Thought Process block per user message.
                      int runStart = index;
                      bool foldThoughtIntoLater = false;
                      List<ChatMessage> mergedPrior = const [];
                      List<String?> mergedPriorResults = const [];
                      if (!isUser) {
                        while (runStart - 1 >= 0 &&
                            messages[runStart - 1].role != MessageRole.user) {
                          runStart--;
                        }
                        int runEnd = index;
                        while (runEnd + 1 < messages.length &&
                            messages[runEnd + 1].role != MessageRole.user) {
                          runEnd++;
                        }
                        int displayIndex = runEnd;
                        while (displayIndex > runStart &&
                            _isPairedResult(messages, displayIndex)) {
                          displayIndex--;
                        }
                        foldThoughtIntoLater = index != displayIndex;
                        if (!foldThoughtIntoLater) {
                          final prior = <ChatMessage>[];
                          final priorResults = <String?>[];
                          for (int k = runStart; k < displayIndex; k++) {
                            if (_isPairedResult(messages, k)) continue;
                            prior.add(messages[k]);
                            priorResults.add(
                              k + 1 < messages.length &&
                                      _isPairedResult(messages, k + 1)
                                  ? messages[k + 1].text
                                  : null,
                            );
                          }
                          mergedPrior = prior;
                          mergedPriorResults = priorResults;
                        }
                      }
                      int groupPrev = index - 1;
                      while (groupPrev >= 0 &&
                          _isPairedResult(messages, groupPrev)) {
                        groupPrev--;
                      }
                      final isFirstOfGroup = isUser
                          ? (groupPrev < 0 ||
                                messages[groupPrev].role !=
                                    messages[index].role)
                          : (runStart <= 0 ||
                                messages[runStart - 1].role !=
                                    messages[index].role);
                      List<int> branchIndicesForVersions = [];
                      int currentVersionIndex = 0;

                      if (isUser && branches != null && branches!.isNotEmpty) {
                        final activeMsgs = messages;
                        final prefix = activeMsgs.sublist(0, index);
                        final seenTexts = <String>{};

                        for (int b = 0; b < branches!.length; b++) {
                          final branchMsgs = branches![b];
                          if (branchMsgs.length > index) {
                            bool matches = true;
                            for (int j = 0; j < index; j++) {
                              if (branchMsgs[j].text != prefix[j].text ||
                                  branchMsgs[j].role != prefix[j].role) {
                                matches = false;
                                break;
                              }
                            }
                            if (matches) {
                              final msgText = branchMsgs[index].text;
                              if (!seenTexts.contains(msgText)) {
                                seenTexts.add(msgText);
                                branchIndicesForVersions.add(b);
                              }
                            }
                          }
                        }

                        currentVersionIndex = branchIndicesForVersions
                            .indexWhere(
                              (bIdx) =>
                                  branches![bIdx][index].text ==
                                  messages[index].text,
                            );
                        if (currentVersionIndex == -1) currentVersionIndex = 0;
                      }

                      return MessageBubble(
                        message: messages[index],
                        index: index,
                        mergedPrior: mergedPrior,
                        mergedPriorResults: mergedPriorResults,
                        foldThoughtIntoLater: foldThoughtIntoLater,
                        isFirstOfGroup: isFirstOfGroup,
                        isLastMessage: index == _lastVisibleIndex(messages),
                        pairedResultText:
                            (index + 1 < messages.length &&
                                _isPairedResult(messages, index + 1))
                            ? messages[index + 1].text
                            : null,
                        reasoningEnabled: settings.reasoningEnabled,
                        animationState: state,
                        agenticWorkspace: agenticWorkspace,
                        fileName: fileName,
                        onOpenSource: onOpenSource,
                        isSending: isSending,
                        isLiveTurn:
                            isSending && !isUser && index > lastUserIndex,
                        onEditUserMessage: () => onEditUserMessage(index),
                        onStartResearch: ([editedStateMap]) =>
                            onStartResearch(index, editedStateMap),
                        versionsCount: branchIndicesForVersions.length,
                        currentVersionIndex: currentVersionIndex,
                        onVersionChanged: branchIndicesForVersions.isEmpty
                            ? null
                            : (int vIdx) {
                                onBranchChanged?.call(
                                  branchIndicesForVersions[vIdx],
                                );
                              },
                        animateEntry: index == _entryAnimationIndex,
                        onRegenerate: !isUser && onRegenerateMessage != null
                            ? () => onRegenerateMessage!(index)
                            : null,
                      );
                    },
                  ),
                ),
                if (todoListVisible && activeTodos.isNotEmpty)
                  Positioned(
                    top: 84,
                    right: 0,
                    bottom: 0,
                    width: 280,
                    child: TodoListPanel(
                      todos: activeTodos,
                      onClose: onCloseTodoList,
                    ),
                  ),
                if (messages.isEmpty) Center(child: _buildEmptyState(context)),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ClipRect(
                    child: LiquidGlassSurface(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(20),
                      ),
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.only(bottom: 2),
                      child: SafeArea(
                        bottom: false,
                        child: ChatHeader(
                          provider: provider,
                          settings: settings,
                          model: model,
                          onOpenProvider: onOpenProvider,
                          onOpenModel: onOpenModel,
                          onOpenLiveVoice: onOpenLiveVoice,
                        ),
                      ),
                    ),
                  ),
                ),
                if (agenticEnabled && activeTodos.isNotEmpty)
                  Positioned(
                    top: 0,
                    right: 76,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: LiquidGlassIconButton(
                          icon: Icons.checklist_rounded,
                          size: 40,
                          tooltip: todoListVisible
                              ? 'Close todo list'
                              : 'Open todo list',
                          iconColor: todoListVisible
                              ? const Color(0xFF059669)
                              : const Color(0xFF5C3D26),
                          onPressed: () => onToggleTodoList?.call(),
                        ),
                      ),
                    ),
                  ),
                if (showJumpToBottom)
                  Positioned(
                    right: 16,
                    bottom: 12,
                    child: _JumpToBottomButton(
                      isSending: isSending,
                      onPressed: onJumpToBottom,
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Composer(
              controller: messageController,
              focusNode: composerFocusNode,
              isSending: isSending,
              onSend: onSend,
              onStop: onStop,
              onPlusPressed: onPlusPressed,
              onOpenLiveVoice: onOpenLiveVoice,
              attachedImages: attachedImages,
              onRemoveImage: onRemoveImage,
              attachedFiles: attachedFiles,
              onRemoveFile: onRemoveFile,
              deepResearchEnabled: deepResearchEnabled,
              isEditing: isEditing,
              onCancelEdit: onCancelEdit,
              activeFeaturePills: activeFeaturePills,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    IconData icon = Icons.auto_awesome_outlined;
    Color iconColor = const Color(0xFF7B4E2E);
    String title = 'How can I help today?';
    String helper =
        'Ask a question, attach something to explore, or start with a suggestion.';
    List<String> suggestions = const [
      'Help me plan my day',
      'Summarize a topic for me',
      'Brainstorm some ideas',
    ];

    if (deepResearchEnabled) {
      icon = Icons.psychology;
      title = 'Deep Research Mode Active';
      helper = 'Please select a model which is good at reasoning and make sure you are using at least 32k context model.';
      suggestions = const [];
    } else if (studyModeEnabled) {
      icon = Icons.school_outlined;
      iconColor = const Color(0xFFB45309);
      title = 'Study Mode Active';
      helper = 'Attach notes or PDFs, ask questions about them, or generate a quiz to practice.';
      suggestions = const [];
    } else if (agenticEnabled) {
      icon = Icons.terminal_rounded;
      iconColor = const Color(0xFF059669);
      title = 'Agentic Mode Active';
      helper = 'Ask Nexon to read, edit, and run tools in your workspace.';
      suggestions = const [];
    }

    return LiquidGlassSurface(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      borderRadius: BorderRadius.circular(20),
      backgroundColor: const Color(0xFFFFF9F2).withValues(alpha: 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFFFBF6EC),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D241C),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            helper,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6C5946),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: suggestions
                  .map(
                    (suggestion) => ActionChip(
                      label: Text(suggestion),
                      labelStyle: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5C3D26),
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: const Color(0xFFFFF8EA),
                      side: const BorderSide(color: Color(0xFFDCCBB8)),
                      onPressed: () => _selectSuggestion(suggestion),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  void _selectSuggestion(String suggestion) {
    if (onSuggestionSelected != null) {
      onSuggestionSelected!(suggestion);
      return;
    }
    messageController.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
    composerFocusNode?.requestFocus();
  }
}

class _JumpToBottomButton extends StatelessWidget {
  const _JumpToBottomButton({required this.isSending, this.onPressed});

  final bool isSending;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        LiquidGlassSurface(
          margin: EdgeInsets.zero,
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(22),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.arrow_downward_rounded,
                  size: 21,
                  color: Color(0xFF5C3D26),
                ),
              ),
            ),
          ),
        ),
        if (isSending) const Positioned(top: 1, right: 1, child: _SendingDot()),
      ],
    );
  }
}

class _SendingDot extends StatefulWidget {
  const _SendingDot();

  @override
  State<_SendingDot> createState() => _SendingDotState();
}

class _SendingDotState extends State<_SendingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: const Color(0xFF059669),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFBF6EC), width: 1.5),
        ),
      ),
    );
  }
}

bool _isToolOutputMessage(ChatMessage m) =>
    m.role == MessageRole.system ||
    m.text.startsWith('Tool Result [') ||
    m.text.startsWith('Search results:\n') ||
    m.text.startsWith('URL Content:\n') ||
    m.text.startsWith('MCP Result:\n') ||
    m.text.startsWith('Web Search results') ||
    m.text.startsWith('Content of URL');

bool _isPairedResult(List<ChatMessage> msgs, int i) =>
    i > 0 &&
    i < msgs.length &&
    _isToolOutputMessage(msgs[i]) &&
    msgs[i - 1].role != MessageRole.user &&
    findNativeToolFence(msgs[i - 1].text) != null;

int _lastVisibleIndex(List<ChatMessage> msgs) {
  int i = msgs.length - 1;
  while (i > 0 && _isPairedResult(msgs, i)) {
    i--;
  }
  return i;
}
