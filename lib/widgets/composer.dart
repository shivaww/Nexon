// Extracted from main.dart lines 12788-13103
// Extracted on: 2026-08-26T18:20:45.714058

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexon/main.dart';

class Composer extends StatelessWidget {
  const Composer({
    required this.controller,
    required this.isSending,
    required this.onSend,
    required this.onPlusPressed,
    required this.attachedImages,
    required this.onRemoveImage,
    required this.attachedFiles,
    required this.onRemoveFile,
    required this.deepResearchEnabled,
    required this.isEditing,
    required this.onCancelEdit,
    this.onStop,
    this.onOpenLiveVoice,
    this.activeFeaturePills = const [],
    super.key,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback? onStop;
  final VoidCallback onPlusPressed;
  final VoidCallback? onOpenLiveVoice;
  final List<String> attachedImages;
  final ValueChanged<int> onRemoveImage;
  final List<AttachedFile> attachedFiles;
  final ValueChanged<int> onRemoveFile;
  final bool deepResearchEnabled;
  final bool isEditing;
  final VoidCallback onCancelEdit;
  final List<Widget> activeFeaturePills;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEditing)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 920),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F6EE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE7D8C4)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.edit_outlined,
                      size: 14,
                      color: Color(0xFF7B4E2E),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Editing message',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF7B4E2E),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: onCancelEdit,
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: Color(0xFF7B4E2E),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (attachedFiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: SizedBox(
                height: 36,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: attachedFiles.length,
                  itemBuilder: (context, idx) {
                    final file = attachedFiles[idx];
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0EBE1),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFDCCBB8)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.insert_drive_file,
                            size: 14,
                            color: Color(0xFF7B4E2E),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            file.name,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4A3424),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => onRemoveFile(idx),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Color(0xFF7B4E2E),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          if (attachedImages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: attachedImages.length,
                  itemBuilder: (context, idx) {
                    return Stack(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFDCCBB8)),
                            image: DecorationImage(
                              image: MemoryImage(
                                base64Decode(attachedImages[idx]),
                              ),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: GestureDetector(
                            onTap: () => onRemoveImage(idx),
                            child: const CircleAvatar(
                              radius: 8,
                              backgroundColor: Colors.black54,
                              child: Icon(
                                Icons.close,
                                size: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final suggestions = SlashCommandService.filterCommands(value.text);
              if (suggestions.isEmpty) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBF2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5DDD3)),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: suggestions.length,
                  itemBuilder: (context, index) {
                    final command = suggestions[index];
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: Text(
                        command,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF4A3424),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () {
                        controller.value = TextEditingValue(
                          text: command.split(' ').first + ' ',
                          selection: TextSelection.collapsed(
                            offset: command.split(' ').first.length + 1,
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
          if (activeFeaturePills.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6.0, left: 4.0),
              child: SizedBox(
                height: 24,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: activeFeaturePills
                      .map((pill) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: pill,
                          ))
                      .toList(),
                ),
              ),
            ),
          // Target #5: Bottom message input -> full-width pill glass container
          LiquidGlassSurface(
            borderRadius: BorderRadius.circular(30),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                LiquidGlassIconButton(
                  icon: Icons.add_rounded,
                  size: 38,
                  onPressed: onPlusPressed,
                  tooltip: 'Attach media or file',
                ),
                if (onOpenLiveVoice != null) ...[
                  const SizedBox(width: 6),
                  LiquidGlassIconButton(
                    icon: Icons.mic_rounded,
                    size: 38,
                    onPressed: onOpenLiveVoice!,
                    tooltip: 'Live Voice Mode',
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 6,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF2D241C),
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Message Nexon...',
                        hintStyle: TextStyle(
                          color: Color(0xFF8C7A6B),
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 4,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                LiquidGlassIconButton(
                  icon: isSending
                      ? Icons.stop_rounded
                      : Icons.arrow_upward_rounded,
                  size: 38,
                  backgroundColor: const Color(0xFF7B4E2E),
                  iconColor: Colors.white,
                  onPressed: isSending ? (onStop ?? () {}) : onSend,
                  tooltip: isSending ? 'Stop response' : 'Send message',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
