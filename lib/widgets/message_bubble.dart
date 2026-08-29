// Extracted from main.dart lines 11114-12293
// Extracted on: 2026-08-26T18:20:45.721319

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:google_fonts/google_fonts.dart';
import 'package:nexon/main.dart';
import 'package:nexon/widgets/nexon_chart.dart';
import 'package:nexon/widgets/diff_viewer_widget.dart';
import 'package:nexon/widgets/scrollable_table_builder.dart';
import 'package:url_launcher/url_launcher.dart';

// ══════════════════════════════════════════════════════════════════════════════

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.index,
    required this.providerShortName,
    required this.providerName,
    required this.reasoningEnabled,
    required this.onEditUserMessage,
    required this.agenticWorkspace,
    required this.fileName,
    required this.isSending,
    this.animationState = AvatarAnimationState.idle,
    this.onStartResearch,
    this.versionsCount = 0,
    this.currentVersionIndex = 0,
    this.onVersionChanged,
    super.key,
  });

  final ChatMessage message;
  final int index;
  final String providerShortName;
  final String providerName;
  final bool reasoningEnabled;
  final String agenticWorkspace;
  final String fileName;
  final AvatarAnimationState animationState;
  final VoidCallback onEditUserMessage;
  final void Function([Map<String, dynamic>? editedStateMap])? onStartResearch;
  final int versionsCount;
  final int currentVersionIndex;
  final ValueChanged<int>? onVersionChanged;
  final bool isSending;

  @override
  Widget build(BuildContext context) {
    final text = message.text;
    final isToolOutput =
        message.role == MessageRole.system ||
        text.startsWith('Tool Result [') ||
        text.startsWith('Search results:\n') ||
        text.startsWith('URL Content:\n') ||
        text.startsWith('MCP Result:\n') ||
        text.startsWith('Web Search results') ||
        text.startsWith('Content of URL');
    final isUser = message.role == MessageRole.user;

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 240 + (index % 5) * 24),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 12),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isToolOutput) ...[
              Row(
                children: [
                  if (isUser) ...[
                    Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF8B5E3C), Color(0xFF6B3F22)],
                        ),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'You',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.1,
                        color: Color(0xFF7B4E2E),
                      ),
                    ),
                    if (versionsCount > 1) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5EFE4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFDCCBB8),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: currentVersionIndex > 0
                                  ? () => onVersionChanged?.call(
                                      currentVersionIndex - 1,
                                    )
                                  : null,
                              child: Icon(
                                Icons.chevron_left,
                                size: 14,
                                color: currentVersionIndex > 0
                                    ? const Color(0xFF7B4E2E)
                                    : const Color(0xFFCBBBA4),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Text(
                                '${currentVersionIndex + 1}/$versionsCount',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF7B4E2E),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: currentVersionIndex < versionsCount - 1
                                  ? () => onVersionChanged?.call(
                                      currentVersionIndex + 1,
                                    )
                                  : null,
                              child: Icon(
                                Icons.chevron_right,
                                size: 14,
                                color: currentVersionIndex < versionsCount - 1
                                    ? const Color(0xFF7B4E2E)
                                    : const Color(0xFFCBBBA4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ] else ...[
                    ProviderAvatar(
                      label: providerShortName,
                      small: true,
                      animationState: animationState,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      providerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF2D241C),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.tokenUsage.isNotEmpty && !isUser)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5EFE4),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFFE7D8C4),
                                width: 0.6,
                              ),
                            ),
                            child: Text(
                              message.tokenUsage,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                                color: Color(0xFF6C5946),
                              ),
                            ),
                          ),
                        ),
                      if (message.tokensPerSec.isNotEmpty && !isUser)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: animationState != AvatarAnimationState.idle
                                  ? const Color(0xFFECFDF5)
                                  : const Color(0xFFF5EFE4),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: animationState != AvatarAnimationState.idle
                                    ? const Color(0xFF6EE7B7)
                                    : const Color(0xFFE7D8C4),
                                width: 0.6,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (animationState != AvatarAnimationState.idle)
                                  Container(
                                    width: 5,
                                    height: 5,
                                    margin: const EdgeInsets.only(right: 4),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF059669),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                Text(
                                  '${message.tokensPerSec} tok/s',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.15,
                                    color: animationState != AvatarAnimationState.idle
                                        ? const Color(0xFF065F46)
                                        : const Color(0xFF6C5946),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      LiquidGlassIconButton(
                        icon: Icons.content_copy_rounded,
                        size: 28,
                        tooltip: 'Copy text',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: message.text));
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Message copied to clipboard'),
                              duration: Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                      if (!isUser) ...[
                        const SizedBox(width: 6),
                        StatefulBuilder(
                          builder: (context, setTtsState) {
                            final speaking = NexonTts.isSpeaking(message.text);
                            return LiquidGlassIconButton(
                              icon: speaking
                                  ? Icons.stop_circle_rounded
                                  : Icons.volume_up_rounded,
                              size: 28,
                              tooltip: speaking
                                  ? 'Stop audio'
                                  : 'Read aloud (TTS)',
                              iconColor: speaking
                                  ? const Color(0xFF9B4D39)
                                  : const Color(0xFF5C3D26),
                              onPressed: () {
                                NexonTts.toggleSpeak(
                                  message.text,
                                  () => setTtsState(() {}),
                                );
                              },
                            );
                          },
                        ),
                      ],
                      if (isUser) ...[
                        const SizedBox(width: 6),
                        LiquidGlassIconButton(
                          icon: Icons.edit_rounded,
                          size: 28,
                          tooltip: 'Edit message',
                          onPressed: onEditUserMessage,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (message.images.isNotEmpty || message.videos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: ChatMediaGrid(
                  images: message.images,
                  videos: message.videos,
                ),
              ),
            if (isToolOutput)
              Builder(
                builder: (context) {
                  // Parse a smart header for tool results
                  final text = message.text;
                  String header;
                  IconData headerIcon;
                  Color headerColor;
                  final hasError =
                      text.contains('"error"') || text.contains('Error:');
                  if (hasError) {
                    headerIcon = Icons.error_outline;
                    headerColor = const Color(0xFFDC2626);
                  } else {
                    headerIcon = Icons.check_circle_outline;
                    headerColor = const Color(0xFF059669);
                  }

                  // Extract tool name from "Tool Result [method]:" or "Web Search results" etc.
                  final toolResultMatch = RegExp(
                    r'Tool Result \[(\w+)\]',
                  ).firstMatch(text);
                  final webSearchMatch =
                      text.startsWith('Web Search results') ||
                      text.startsWith('Search results:\n');
                  final urlMatch =
                      text.startsWith("Content of URL") ||
                      text.startsWith("URL Content:\n");
                  final mcpMatch = text.startsWith("MCP Result:\n");
                  if (toolResultMatch != null) {
                    final method = toolResultMatch.group(1) ?? 'tool';
                    final sizeKb = (text.length / 1024).toStringAsFixed(1);
                    header = hasError
                        ? '❌ Failed: $method'
                        : '✅ Tool Result [$method]  ·  ${sizeKb} KB';
                    headerIcon = hasError
                        ? Icons.error_outline
                        : Icons.check_circle_outline;
                  } else if (webSearchMatch) {
                    header = '🔍 Web Search Results';
                    headerIcon = Icons.search;
                    headerColor = const Color(0xFF0369A1);
                  } else if (urlMatch) {
                    header = '🌐 URL Content Fetched';
                    headerIcon = Icons.language;
                    headerColor = const Color(0xFF0369A1);
                  } else if (mcpMatch) {
                    header = '⚙️ MCP Tool Result';
                    headerIcon = Icons.settings;
                    headerColor = const Color(0xFF059669);
                  } else {
                    header = text.split('\n').first;
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: headerColor.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: headerColor.withOpacity(0.18)),
                      boxShadow: [
                        BoxShadow(
                          color: headerColor.withOpacity(0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ExpansionTile(
                      title: Text(
                        header,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: headerColor,
                          fontFamily: 'monospace',
                        ),
                      ),
                      leading: Icon(headerIcon, color: headerColor, size: 17),
                      collapsedBackgroundColor: Colors.transparent,
                      backgroundColor: Colors.transparent,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: webSearchMatch
                                  ? [_buildMarkdownResult(context, message.text)]
                                  : _buildToolResultDetails(
                                      context,
                                      message.text,
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              )
            else if (isUser)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFFDF9), Color(0xFFF9F1E3)],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(5),
                  ),
                  border: Border.all(color: Color(0xFFE7D8C4), width: 0.8),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x0F7B4E2E),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.files.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: message.files
                              .map(
                                (f) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0xFFE7D8C4),
                                      width: 0.7,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 6,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.insert_drive_file,
                                        size: 13,
                                        color: Color(0xFF7B4E2E),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        f.name,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: Color(0xFF4A3424),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    SelectableText(
                      message.text,
                      style: const TextStyle(
                        height: 1.55,
                        color: Color(0xFF2D241C),
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              if (message.reasoning.isNotEmpty && reasoningEnabled)
                ThoughtBlock(thought: message.reasoning),
              ..._parseRichMessageContent(context, message.text),
              if (animationState != AvatarAnimationState.idle)
                const StreamingCursor(),
            ],
            const SizedBox(height: 10),
            Divider(
              color: const Color(0xFFE7D8C4).withOpacity(0.5),
              height: 1,
              thickness: 0.6,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _parseRichMessageContent(BuildContext context, String text) {
    final widgets = <Widget>[];
    int currentIndex = 0;

    final tags = [
      (tag: '<search_request>', isXml: false),
      (tag: '<read_url>', isXml: false),
      (tag: '<mcp_request>', isXml: false),
      (tag: '<tool_request>', isXml: true),
      (tag: '<command>', isXml: true),
      (tag: '<workspace_list>', isXml: false),
      (tag: '<workspace_search>', isXml: false),
      (tag: '<workspace_cross_compare>', isXml: false),
      (tag: '<workspace_read_page>', isXml: false),
      (tag: '<workspace_get_outline>', isXml: false),
      (tag: '<workspace_ingest>', isXml: false),
    ];

    while (currentIndex < text.length) {
      final substring = text.substring(currentIndex);

      // Native JSON tool calls: fenced ```json blocks shaped {"t":...} or
      // {"calls":[...]} render as tool blocks, just like the legacy tags.
      final toolFence = findNativeToolFence(substring);
      final researchFence = findFenceWithKeys(
        substring,
        const ['research_plan', 'research_state'],
      );
      int earliestIndex = -1;
      var matchedTag = tags.first;

      for (final tagInfo in tags) {
        final idx = substring.indexOf(tagInfo.tag);
        if (idx != -1) {
          if (earliestIndex == -1 || idx < earliestIndex) {
            earliestIndex = idx;
            matchedTag = tagInfo;
          }
        }
      }

      if (researchFence != null &&
          (toolFence == null ||
              (researchFence['start'] as int) < toolFence.start) &&
          (earliestIndex == -1 ||
              (researchFence['start'] as int) < earliestIndex)) {
        final textBefore =
            substring.substring(0, researchFence['start'] as int).trim();
        if (textBefore.isNotEmpty) {
          widgets.addAll(_buildBlocks(context, textBefore));
        }
        final rj = researchFence['json'] as Map<String, dynamic>;
        if (rj['research_state'] is Map<String, dynamic>) {
          widgets.add(
            ResearchPlanWidget(
              stateMap: rj['research_state'] as Map<String, dynamic>,
              workspaceDir: agenticWorkspace,
              fileName: fileName,
              isSending: isSending,
              onStartResearch: onStartResearch,
            ),
          );
        } else {
          widgets.add(const SizedBox.shrink());
        }
        currentIndex += researchFence['end'] as int;
        continue;
      }

      if (toolFence != null &&
          (earliestIndex == -1 || toolFence.start < earliestIndex)) {
        final textBefore = substring.substring(0, toolFence.start).trim();
        if (textBefore.isNotEmpty) {
          widgets.addAll(_buildBlocks(context, textBefore));
        }
        final fenceCalls = toolFence.json['calls'] is List
            ? (toolFence.json['calls'] as List)
                  .whereType<Map<String, dynamic>>()
                  .toList()
            : <Map<String, dynamic>>[toolFence.json];
        for (final fenceCall in fenceCalls) {
          widgets.add(
            McpToolBlock(
              mcpJson: jsonEncode({
                'method': fenceCall['t']?.toString() ?? 'tool',
                'params': fenceCall['a'] ?? <String, dynamic>{},
              }),
              isXml: false,
            ),
          );
        }
        currentIndex += toolFence.end;
        continue;
      }

      if (earliestIndex == -1) {
        final remaining = substring.trim();
        if (remaining.isNotEmpty) {
          widgets.addAll(_buildBlocks(context, remaining));
        }
        break;
      }

      final textBefore = substring.substring(0, earliestIndex).trim();
      if (textBefore.isNotEmpty) {
        widgets.addAll(_buildBlocks(context, textBefore));
      }

      final tagStartIndex = currentIndex + earliestIndex;
      final openTag = matchedTag.tag;
      final closeTag = openTag.replaceFirst('<', '</');

      final tagContentStartIndex = tagStartIndex + openTag.length;
      final closeTagIndexInFull = text.indexOf(closeTag, tagContentStartIndex);

      if (closeTagIndexInFull == -1) {
        // Unclosed tag (streaming fallback)
        final contentStr = text.substring(tagContentStartIndex).trim();
        widgets.add(
          _buildSpecializedWidget(openTag, contentStr, matchedTag.isXml),
        );
        break;
      }

      final contentStr = text
          .substring(tagContentStartIndex, closeTagIndexInFull)
          .trim();
      widgets.add(
        _buildSpecializedWidget(openTag, contentStr, matchedTag.isXml),
      );

      currentIndex = closeTagIndexInFull + closeTag.length;
    }

    return widgets;
  }

  Widget _buildSpecializedWidget(String openTag, String content, bool isXml) {
    try {
      switch (openTag) {
        case '<research_plan>':
          return const SizedBox.shrink();
        case '<research_state>':
          {
            var cleanContent = content;
            if (cleanContent.contains('<research_plan>')) {
              final planIndex = cleanContent.indexOf('<research_plan>');
              final planEndIndex = cleanContent.indexOf(
                '</research_plan>',
                planIndex,
              );
              if (planEndIndex != -1) {
                cleanContent =
                    (cleanContent.substring(0, planIndex) +
                            cleanContent.substring(planEndIndex + 16))
                        .trim();
              } else {
                cleanContent = cleanContent.substring(0, planIndex).trim();
              }
            }
            final stateMap = jsonDecode(cleanContent) as Map<String, dynamic>;
            return ResearchPlanWidget(
              stateMap: stateMap,
              workspaceDir: agenticWorkspace,
              fileName: fileName,
              isSending: isSending,
              onStartResearch: onStartResearch,
            );
          }
        case '<search_request>':
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F5FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD0E0F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: Color(0xFF2B6CB0), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tool Use: Searched the web for "$content"',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2B6CB0),
                    ),
                  ),
                ),
              ],
            ),
          );
        case '<read_url>':
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F5FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD0E0F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.link, color: Color(0xFF2B6CB0), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tool Use: Reading webpage at "$content"',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2B6CB0),
                    ),
                  ),
                ),
              ],
            ),
          );
        case '<command>':
          final contentStr =
              '<method>run_command</method><command>$content</command>';
          return McpToolBlock(mcpJson: contentStr, isXml: true);
        case '<workspace_list>':
        case '<workspace_search>':
        case '<workspace_read_page>':
        case '<workspace_get_outline>':
        case '<workspace_ingest>':
          return _buildWorkspaceResultBlock(openTag, content);
        default: // <mcp_request>, <tool_request>
          return McpToolBlock(mcpJson: content, isXml: isXml);
      }
    } catch (e) {
      return Text(
        'Error rendering $openTag: $e',
        style: const TextStyle(color: Colors.red),
      );
    }
  }

  /// IMPROVEMENT: Renders workspace tool results (<workspace_list>,
  /// <workspace_search>, etc.) as collapsible blocks instead of raw JSON text.
  Widget _buildWorkspaceResultBlock(String openTag, String content) {
    final method = openTag.replaceAll(RegExp('[<>/]'), '');
    String header;
    IconData icon;
    Color accent;
    final List<Widget> detailChildren = [];

    const monoStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      color: Color(0xFF52606D),
    );

    try {
      final decoded = jsonDecode(content);
      if (method == 'workspace_list' && decoded is Map) {
        final files = (decoded['files'] as List?) ?? [];
        final usedMb = decoded['used_quota_mb']?.toString() ??
            decoded['total_used_mb']?.toString() ?? '';
        final totalMb = decoded['quota_mb']?.toString() ??
            decoded['total_quota_mb']?.toString() ?? '';
        header = 'Workspace files (${files.length})' +
            (usedMb.isNotEmpty ? ' · $usedMb/$totalMb MB used' : '');
        icon = Icons.folder_open_outlined;
        accent = const Color(0xFFD97706);
        for (final f in files.whereType<Map>()) {
          final name = f['path']?.toString() ??
              f['file']?.toString() ??
              f['name']?.toString() ?? 'file';
          final sizeBytes = (f['size_bytes'] as num? ??
              ((f['size_kb'] as num? ?? 0) * 1024));
          final sizeKb = (sizeBytes / 1024).toStringAsFixed(1);
          detailChildren.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.insert_drive_file,
                    size: 14,
                    color: Color(0xFF8B7355),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2D241C),
                      ),
                    ),
                  ),
                  Text(
                    '$sizeKb KB',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8B7355),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      } else if (method == 'workspace_search') {
        List<dynamic> rawMatches = [];
        if (decoded is Map) {
          rawMatches = (decoded['matches'] as List?) ??
              (decoded['results'] as List?) ?? [];
        } else if (decoded is List) {
          rawMatches = decoded;
        }
        header = 'Workspace search (${rawMatches.length} matches)';
        icon = Icons.manage_search_outlined;
        accent = const Color(0xFF0369A1);
        for (final m in rawMatches.whereType<Map>().take(8)) {
          final file = m['file_path']?.toString() ??
              m['file']?.toString() ??
              m['relative_path']?.toString() ?? '';
          final section = m['section']?.toString() ??
              m['chunk_id']?.toString() ?? '';
          final excerpt = m['excerpt']?.toString() ??
              m['content']?.toString() ?? '';
          detailChildren.add(
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBF2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE7D8C4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file + (section.isNotEmpty ? ' — $section' : ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2D241C),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    excerpt,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF52606D),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      } else {
        header = 'Workspace result';
        icon = Icons.work_outline;
        accent = const Color(0xFF059669);
        detailChildren.add(SelectableText(content, style: monoStyle));
      }
    } catch (_) {
      header = 'Workspace result';
      icon = Icons.work_outline;
      accent = const Color(0xFF059669);
      detailChildren.add(SelectableText(content, style: monoStyle));
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        collapsedBackgroundColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        leading: Icon(icon, color: accent, size: 18),
        title: Text(
          header,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
        children: detailChildren.isEmpty
            ? [const SizedBox.shrink()]
            : detailChildren,
      ),
    );
  }

  Widget _buildMarkdownResult(BuildContext context, String text) {
    final lines = text.split('\n');
    final contentStart = lines.indexWhere((l) => l.trim().isNotEmpty && !l.startsWith('🔍'));
    final content = contentStart > 0 ? lines.sublist(contentStart).join('\n') : text;
    return MarkdownBody(
      data: content.trim(),
      selectable: true,
      onTapLink: (url, _, __) async {
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        }
      },
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF2D241C)),
        a: const TextStyle(color: Color(0xFF0369A1), decoration: TextDecoration.underline),
        listBullet: const TextStyle(color: Color(0xFF6C5946)),
      ),
    );
  }

  List<Widget> _buildToolResultDetails(BuildContext context, String text) {
    final sections = text.split(RegExp(r'\n\n---\n\n'));
    return sections
        .where((section) => section.trim().isNotEmpty)
        .map((section) => _buildToolResultSection(context, section.trim()))
        .toList();
  }

  Widget _buildToolResultSection(BuildContext context, String section) {
    var body = section;
    final firstBreak = body.indexOf('\n\n');
    if (body.startsWith('Tool Result [') && firstBreak != -1) {
      body = body.substring(firstBreak + 2);
    } else if (body.startsWith('MCP Result:\n')) {
      body = body.substring('MCP Result:\n'.length);
    }

    String? diff;
    if (body.contains('--- DIFF ---')) {
      final parts = body.split('--- DIFF ---');
      body = parts.first.trim();
      diff = parts.skip(1).join('--- DIFF ---').trim();
    }

    final embeddedDiffIndex = body.indexOf('\nDIFF:\n');
    if (embeddedDiffIndex != -1 && diff != null) {
      body = body.substring(0, embeddedDiffIndex).trim();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (body.trim().isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1915),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              body.trim(),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                height: 1.35,
                color: Color(0xFFFFF7EC),
              ),
            ),
          ),
        if (diff != null && diff.trim().isNotEmpty)
          DiffViewerWidget(content: diff.trim()),
      ],
    );
  }

  List<Widget> _buildBlocks(BuildContext context, String text) {
    if (text.startsWith("Tool Result [") && text.contains("\n\n")) {
      final resultContent = text.substring(text.indexOf("\n\n") + 2);
      if (resultContent.contains("--- DIFF ---")) {
        final parts = resultContent.split("--- DIFF ---");
        return [
          ...parseContentBlocks(parts[0].trim()).map((block) {
            return _buildSingleBlock(context, block);
          }).toList(),
          if (parts.length > 1 && parts[1].trim().isNotEmpty)
            DiffViewerWidget(content: parts[1].trim()),
        ];
      }
      return [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade800),
          ),
          child: SelectableText(
            resultContent,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: Color(0xFFD4D4D4),
            ),
          ),
        ),
      ];
    }
    final blocks = parseContentBlocks(text);
    // While streaming, the last ``` fence is still open — render that final
    // block as a lightweight streaming view so tokens flow in smoothly, and
    // swap to the rich artifact widget once the fence closes.
    final unclosedFence = text.split('```').length % 2 == 0;
    final widgets = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final streaming = animationState != AvatarAnimationState.idle &&
          i == blocks.length - 1 &&
          block.isCode &&
          unclosedFence;
      final isVisualLang = const {'svg', 'chart', 'json-chart'}
          .contains(block.language.toLowerCase());
      widgets.add(
        streaming
            ? (isVisualLang
                  ? const _VisualStreamingPlaceholder()
                  : StreamingCodeBlock(code: block.content, language: block.language))
            : _buildSingleBlock(context, block),
      );
    }
    return widgets;
  }

  Widget _buildSingleBlock(BuildContext context, ContentBlock block) {
    if (block.isCode) {
      if (block.language.toLowerCase() == 'math') {
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCF6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE7D8C4)),
          ),
          child: SelectableText(
            convertLatexToUnicode(block.content),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D241C),
              fontStyle: FontStyle.italic,
            ),
          ),
        );
      }
      if (block.language.toLowerCase() == 'svg') {
        if (!block.content.contains('</svg>')) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFCF6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE7D8C4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text(
                  'Rendering visual…',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6C5946)),
                ),
              ],
            ),
          );
        }
        return SvgDiagramWidget(svgString: block.content);
      }
      if (block.language.toLowerCase() == 'chart' ||
          block.language.toLowerCase() == 'json-chart') {
        return NexonChartWidget(chartBlock: block.content);
      }
      final lang = block.language.toLowerCase();
      final contentLower = block.content.toLowerCase();
      final isCompleteWebpage =
          contentLower.contains('<html') || contentLower.contains('<!doctype');
      final lineCount = '\n'.allMatches(block.content).length + 1;
      final isCompleteCodeFile =
          lineCount >= 35 ||
          contentLower.contains('void main(') ||
          contentLower.contains('def main(') ||
          contentLower.contains('if __name__') ||
          RegExp(r'^\s*(class|public class|abstract class|private class)\s+', multiLine: true).hasMatch(block.content) ||
          RegExp(r'^\s*(function|export function|async function|export default function)\s+', multiLine: true).hasMatch(block.content);
      final isArtifact =
          lang == 'artifact' ||
          ((lang == 'html' || lang == 'react' || lang == 'javascript') &&
              isCompleteWebpage);
      if (isArtifact) {
        return HtmlArtifactWidget(htmlContent: block.content);
      }
      if (isCompleteCodeFile &&
          {
            'python',
            'py',
            'dart',
            'javascript',
            'js',
            'typescript',
            'ts',
            'html',
            'css',
            'json',
            'yaml',
            'yml',
            'bash',
            'sh',
            'java',
            'kotlin',
            'go',
            'rust',
            'rs',
          }.contains(lang)) {
        return FileArtifactWidget(content: block.content, language: lang);
      }
      if (block.language.toLowerCase() == 'docx') {
        return DocxArtifactWidget(
          docxContent: block.content,
          workspacePath: agenticWorkspace,
        );
      }
      if (block.language.toLowerCase() == 'md' ||
          block.language.toLowerCase() == 'markdown') {
        return MdArtifactWidget(
          mdContent: block.content,
          workspacePath: agenticWorkspace,
        );
      }
      return CodeBlockWidget(
        code: block.content,
        language: block.language,
        onSave: () => saveCodeBlock(context, block.content, block.language),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6.0),
        child: MarkdownBody(
          data: block.content
              .replaceAllMapped(
                RegExp(r'\\\[([\s\S]*?)\\\]'),
                (m) => '\$\$' + (m.group(1) ?? '') + '\$\$',
              )
              .replaceAllMapped(
                RegExp(r'\\\(([\s\S]*?)\\\)'),
                (m) => '\$' + (m.group(1) ?? '') + '\$',
              )
              .replaceAll(r'\boldsymbol', r'\mathbf'),
          selectable: true,
          builders: {
            'latex': LatexElementBuilder(
              textStyle: const TextStyle(
                color: Color(0xFF1E1E1E),
                fontSize: 15.5,
                fontWeight: FontWeight.w400,
              ),
              textScaleFactor: 1.15,
            ),
          },
          extensionSet: md.ExtensionSet(
            [
              LatexBlockSyntax(),
              ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
            ],
            [
              LatexInlineSyntax(),
              ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
            ],
          ),
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: const TextStyle(
              height: 1.48,
              color: Color(0xFF1E1E1E),
              fontSize: 15.5,
              fontWeight: FontWeight.w400,
            ),
            h1: const TextStyle(
              color: Color(0xFF2D241C),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            h2: const TextStyle(
              color: Color(0xFF2D241C),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            h3: const TextStyle(
              color: Color(0xFF2D241C),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            listBullet: const TextStyle(
              color: Color(0xFF7B4E2E),
              fontSize: 15.5,
            ),
            tableBorder: TableBorder.all(
              color: const Color(0xFFDCCBB8),
              width: 1,
            ),
            tableBody: const TextStyle(color: Color(0xFF1E1E1E), fontSize: 14),
            tableHead: const TextStyle(
              color: Color(0xFF2D241C),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            tableColumnWidth: const IntrinsicColumnWidth(),
            tableHeadAlign: TextAlign.left,
            tableCellsPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
        ),
      );
    }
  }
}

class _VisualStreamingPlaceholder extends StatelessWidget {
  const _VisualStreamingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7D8C4)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            'Rendering visual…',
            style: TextStyle(fontSize: 12, color: Color(0xFF6C5946)),
          ),
        ],
      ),
    );
  }
}
