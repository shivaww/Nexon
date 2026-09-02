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

class ChatSurface extends StatelessWidget {
  const ChatSurface({
    required this.provider,
    required this.settings,
    required this.model,
    required this.messages,
    required this.messageController,
    required this.scrollController,
    required this.isSending,
    required this.toolStatus,
    this.activeTodos = const [],
    this.todoListVisible = false,
    this.onCloseTodoList,
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
    this.onOpenLiveVoice,
    this.activeFeaturePills = const [],
    super.key,
  });

  final ProviderDefinition provider;
  final ProviderSettings settings;
  final String model;
  final List<ChatMessage> messages;
  final TextEditingController messageController;
  final ScrollController scrollController;
  final bool isSending;
  final String toolStatus;
  final List<TodoItem> activeTodos;
  final bool todoListVisible;
  final VoidCallback? onCloseTodoList;
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
  final List<List<ChatMessage>>? branches;
  final int? activeBranchIndex;
  final ValueChanged<int>? onBranchChanged;
  final List<Widget> activeFeaturePills;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFBF6EC), Color(0xFFF5EFE4), Color(0xFFEFE5D5)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(18, 84, 18, 90),
              itemCount: messages.length,
              itemBuilder: (context, int index) {
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
                final isFirstOfGroup = index == 0 ||
                    messages[index - 1].role != messages[index].role;
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

                  currentVersionIndex = branchIndicesForVersions.indexWhere(
                    (bIdx) =>
                        branches![bIdx][index].text == messages[index].text,
                  );
                  if (currentVersionIndex == -1) currentVersionIndex = 0;
                }

                return MessageBubble(
                  message: messages[index],
                  index: index,
                  isFirstOfGroup: isFirstOfGroup,
                  providerShortName: provider.shortName,
                  providerName: provider.name,
                  reasoningEnabled: settings.reasoningEnabled,
                  animationState: state,
                  agenticWorkspace: agenticWorkspace,
                  fileName: fileName,
                  isSending: isSending,
                  onEditUserMessage: () => onEditUserMessage(index),
                  onStartResearch: ([editedStateMap]) =>
                      onStartResearch(index, editedStateMap),
                  versionsCount: branchIndicesForVersions.length,
                  currentVersionIndex: currentVersionIndex,
                  onVersionChanged: branchIndicesForVersions.isEmpty
                      ? null
                      : (int vIdx) {
                          onBranchChanged?.call(branchIndicesForVersions[vIdx]);
                        },
                );
              },
            ),
          ),
          if (todoListVisible && activeTodos.isNotEmpty)
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: 280,
              child: TodoListPanel(
                todos: activeTodos,
                onClose: onCloseTodoList,
              ),
            ),
          if (messages.isEmpty && deepResearchEnabled)
            Center(
              child: LiquidGlassSurface(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                borderRadius: BorderRadius.circular(20),
                backgroundColor: const Color(
                  0xFFFFF9F2,
                ).withValues(alpha: 0.85),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFBF6EC),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.psychology,
                        color: Color(0xFF7B4E2E),
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Deep Research Mode Active',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D241C),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Please select a model which is good at reasoning and make sure you are using at least 32k context model.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6C5946),
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
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
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: toolStatus.isNotEmpty
                      ? LiquidGlassSurface(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          backgroundColor: const Color(
                            0xFFF5EFE4,
                          ).withValues(alpha: 0.85),
                          highlightColor: const Color(0xFFDCCBB8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 9,
                            ),
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
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF6C5946),
                                      fontFamily: 'monospace',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Composer(
                  controller: messageController,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
