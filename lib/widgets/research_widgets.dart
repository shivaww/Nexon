// Extracted from main.dart lines 18817-19861
// Extracted on: 2026-08-26T18:20:45.695732

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexon/main.dart';
import 'package:nexon/services/deep_research/deep_research_helpers.dart';
import 'package:nexon/services/deep_research/deep_research_prompts.dart';

class ResearchPlanWidget extends StatefulWidget {
  const ResearchPlanWidget({
    required this.stateMap,
    required this.workspaceDir,
    required this.fileName,
    required this.isSending,
    this.onStartResearch,
    super.key,
  });
  final Map<String, dynamic> stateMap;
  final String workspaceDir;
  final String fileName;
  final bool isSending;
  final void Function([Map<String, dynamic>? editedStateMap])? onStartResearch;

  @override
  State<ResearchPlanWidget> createState() => _ResearchPlanWidgetState();
}

class _ResearchPlanWidgetState extends State<ResearchPlanWidget> {
  final Set<int> _expandedSteps = {};
  late final Stopwatch _stopwatch;
  Timer? _timer;

  Future<void> _editPlan() async {
    final originalSteps = widget.stateMap['steps'] as List? ?? [];
    final controllers = originalSteps.map((step) {
      final value = step as Map;
      return TextEditingController(
        text:
            value['query_text']?.toString() ??
            value['prompt']?.toString() ??
            '',
      );
    }).toList();
    final titles = originalSteps
        .map((step) => (step as Map)['title']?.toString() ?? 'Research stage')
        .toList();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Edit Research Plan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: controllers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) => TextField(
                  controller: controllers[index],
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: titles[index],
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check),
              label: const Text('Save Plan'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      final updatedSteps = <Map<String, dynamic>>[];
      for (var index = 0; index < originalSteps.length; index++) {
        final step = Map<String, dynamic>.from(originalSteps[index] as Map);
        step['query_text'] = controllers[index].text.trim();
        updatedSteps.add(step);
      }
      setState(() => widget.stateMap['steps'] = updatedSteps);
    }
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch();
    final status = widget.stateMap['status'] as String? ?? 'running';
    final isRunning = status == 'running' && widget.isSending;
    if (isRunning) {
      _stopwatch.start();
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        final currentStatus = widget.stateMap['status'] as String? ?? 'running';
        final currentRunning = currentStatus == 'running' && widget.isSending;
        if (currentRunning) {
          if (!_stopwatch.isRunning) {
            _stopwatch.start();
          }
          setState(() {});
        } else {
          if (_stopwatch.isRunning) {
            _stopwatch.stop();
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _downloadFile({bool asDocx = false}) async {
    String contentToSave = widget.stateMap['final_report'] as String? ?? '';
    if (contentToSave.isEmpty) {
      final steps = widget.stateMap['steps'] as List? ?? [];
      for (final step in steps) {
        contentToSave += '# ${step['title']}\n\n${step['content']}\n\n';
      }
    }

    if (contentToSave.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No research content to save.')),
        );
      }
      return;
    }

    try {
      final List<int> bytesList;
      final String targetFileName;

      if (asDocx) {
        final elements = await MarkdownParser.parse(contentToSave);
        final doc = DocxBuiltDocument(elements: elements);
        bytesList = await DocxExporter().exportToBytes(doc);

        String docxName = 'research_report.docx';
        if (widget.fileName.isNotEmpty) {
          final base = widget.fileName.split('.').first;
          docxName = '$base.docx';
        }
        targetFileName = docxName;
      } else {
        bytesList = utf8.encode(contentToSave);
        targetFileName = widget.fileName;
      }

      final bytes = Uint8List.fromList(bytesList);
      final String? path = await FilePicker.platform.saveFile(
        dialogTitle: asDocx ? 'Save Word Document' : 'Save Research Report',
        fileName: targetFileName,
        bytes: bytes,
      );

      if (path == null) {
        return;
      }

      if (!Platform.isAndroid && !Platform.isIOS) {
        final file = File(path);
        await file.writeAsBytes(bytes);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to ${path.split('/').last}'),
            backgroundColor: const Color(0xFF36764D),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving file: $e'),
            backgroundColor: const Color(0xFF9B4D39),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.stateMap['steps'] as List? ?? [];
    final status = widget.stateMap['status'] as String? ?? 'running';

    return LiquidGlassSurface(
      margin: const EdgeInsets.only(bottom: 12, top: 4),
      borderRadius: BorderRadius.circular(16),
      backgroundColor: const Color(0xFFEAF3FF).withValues(alpha: 0.85),
      highlightColor: const Color(0xFF90CDF4),
      shadowColor: const Color(0xFF2C5282),
      enableBlur: false, // In-feed scrolling list performance optimization
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xD9D7E9FA), Color(0xBFD9ECFA)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _ResearchAgentAvatars(
                        status: status,
                        isSending: widget.isSending,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          status == 'completed'
                              ? 'Deep Research Complete'
                              : status == 'pending'
                              ? 'Research Plan Ready'
                              : (status == 'running' && !widget.isSending)
                              ? 'Deep Research Interrupted'
                              : 'Deep Research in Progress...',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2C5282),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (status == 'pending' ||
                    (status == 'running' && !widget.isSending) ||
                    status == 'failed') ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (status == 'pending')
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          tooltip: 'Edit research plan',
                          onPressed: _editPlan,
                          icon: const Icon(Icons.edit_outlined, size: 19),
                          color: const Color(0xFF2C5282),
                        ),
                      if (status == 'pending') const SizedBox(width: 4),
                      if (widget.onStartResearch != null)
                        FilledButton.icon(
                          onPressed: () =>
                              widget.onStartResearch!(widget.stateMap),
                          icon: Icon(
                            status == 'running'
                                ? Icons.play_arrow
                                : (status == 'failed'
                                      ? Icons.replay
                                      : Icons.play_arrow),
                            size: 16,
                          ),
                          label: Text(
                            status == 'running'
                                ? 'Resume'
                                : (status == 'failed' ? 'Retry' : 'Start'),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2C5282),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            minimumSize: const Size(0, 32),
                          ),
                        ),
                    ],
                  ),
                ],
                if (status == 'running' && widget.isSending)
                  Text(
                    '${_stopwatch.elapsed.inMinutes.toString().padLeft(2, '0')}:${(_stopwatch.elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C5282),
                    ),
                  ),
                if (status == 'completed')
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.download,
                      size: 20,
                      color: Color(0xFF2C5282),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (value) {
                      if (value == 'markdown') {
                        _downloadFile(asDocx: false);
                      } else if (value == 'docx') {
                        _downloadFile(asDocx: true);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'docx',
                        child: Row(
                          children: [
                            Icon(
                              Icons.description,
                              size: 18,
                              color: Color(0xFF2C5282),
                            ),
                            SizedBox(width: 8),
                            Text('Save as DOCX'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'markdown',
                        child: Row(
                          children: [
                            Icon(
                              Icons.article,
                              size: 18,
                              color: Color(0xFF2C5282),
                            ),
                            SizedBox(width: 8),
                            Text('Save as Markdown'),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (steps.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: LinearProgressIndicator(
                value:
                    steps
                        .where(
                          (step) =>
                              step['status'] == 'completed' ||
                              step['status'] == 'completed_with_issues',
                        )
                        .length /
                    steps.length,
                backgroundColor: const Color(0xFFCFE0EE),
                color: const Color(0xFF2C5282),
                minHeight: 5,
              ),
            ),
          ...steps.asMap().entries.map((entry) {
            final idx = entry.key;
            final step = entry.value as Map<String, dynamic>;
            final stepStatus = step['status'] as String? ?? 'pending';
            final isExpanded = _expandedSteps.contains(idx);

            IconData statusIcon = Icons.radio_button_unchecked;
            Color statusColor = Colors.grey;
            if (stepStatus == 'running') {
              statusIcon = Icons.hourglass_bottom;
              statusColor = Colors.blue;
            } else if (stepStatus == 'completed') {
              statusIcon = Icons.check_circle;
              statusColor = Colors.green;
            } else if (stepStatus == 'completed_with_issues') {
              statusIcon = Icons.warning_amber;
              statusColor = Colors.orange;
            } else if (stepStatus == 'failed') {
              statusIcon = Icons.error_outline;
              statusColor = Colors.red;
            }

            return Column(
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      if (isExpanded)
                        _expandedSteps.remove(idx);
                      else
                        _expandedSteps.add(idx);
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(statusIcon, size: 18, color: statusColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            (step['title'] as String?) ?? 'Step ${idx + 1}',
                            style: TextStyle(
                              decoration:
                                  (stepStatus == 'completed' ||
                                      stepStatus == 'completed_with_issues')
                                  ? TextDecoration.lineThrough
                                  : null,
                              color:
                                  (stepStatus == 'completed' ||
                                      stepStatus == 'completed_with_issues')
                                  ? Colors.grey
                                  : Colors.black87,
                              fontWeight: stepStatus == 'running'
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 18,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                ),
                if (isExpanded)
                  Container(
                    padding: const EdgeInsets.fromLTRB(40, 0, 14, 12),
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Prompt: ${step['query_text'] ?? step['prompt'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.black54,
                          ),
                        ),
                        if ((step['events'] as List? ?? []).isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: (step['events'] as List).length,
                            itemBuilder: (context, eventIndex) {
                              final event =
                                  (step['events'] as List)[eventIndex] as Map;
                              return _ResearchEventRow(
                                key: ValueKey(
                                  event['id']?.toString() ??
                                      'legacy-event-$eventIndex',
                                ),
                                event: event,
                              );
                            },
                          ),
                        ],
                        if (step['content'] != null &&
                            step['content'].toString().isNotEmpty)
                          ...step['content']
                              .toString()
                              .split('\n\n')
                              .where((s) => s.trim().isNotEmpty)
                              .map((s) {
                                if (s.contains('<mcp_request>')) {
                                  final jsonStr = s
                                      .substring(
                                        s.indexOf('<mcp_request>') + 13,
                                        s.indexOf('</mcp_request>'),
                                      )
                                      .trim();
                                  return McpToolBlock(mcpJson: jsonStr);
                                } else if (s.contains('<search_request>')) {
                                  final query = s
                                      .substring(
                                        s.indexOf('<search_request>') + 16,
                                        s.indexOf('</search_request>'),
                                      )
                                      .trim();
                                  return Container(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0F5FA),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFFD0E0F0),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.search,
                                          color: Color(0xFF2B6CB0),
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Searched the web for "$query"',
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF2B6CB0),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                } else if (s.contains('<read_url>')) {
                                  final url = s
                                      .substring(
                                        s.indexOf('<read_url>') + 10,
                                        s.indexOf('</read_url>'),
                                      )
                                      .trim();
                                  return Container(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0F5FA),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFFD0E0F0),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.link,
                                          color: Color(0xFF2B6CB0),
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Read webpage at "$url"',
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF2B6CB0),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    s,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.black54,
                                    ),
                                  ),
                                );
                              }),
                      ],
                    ),
                  ),
                if (idx < steps.length - 1)
                  const Divider(
                    height: 1,
                    indent: 40,
                    color: Color(0xFFE2ECF5),
                  ),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }
}

class _ResearchEventRow extends StatefulWidget {
  const _ResearchEventRow({super.key, required this.event});

  final Map event;

  @override
  State<_ResearchEventRow> createState() => _ResearchEventRowState();
}

class _ResearchEventRowState extends State<_ResearchEventRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathCtrl;
  var _expanded = false;

  bool get _isRunning => widget.event['status'] == 'running';
  bool get _isIngesting => widget.event['status'] == 'ingesting';
  bool get _isError => widget.event['status'] == 'error';
  bool get _isPulsing => _isRunning || _isIngesting;
  bool get _canExpand {
    if (_isRunning) return false;
    if (_isError || _isIngesting) return true;
    final payload = widget.event['result_payload'];
    return payload is Map && payload.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _breathCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _syncBreathing();
  }

  @override
  void didUpdateWidget(covariant _ResearchEventRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBreathing();
    if (_isRunning && _expanded) _expanded = false;
  }

  void _syncBreathing() {
    if (_isPulsing && !_breathCtrl.isAnimating) {
      _breathCtrl.repeat(reverse: true);
    } else if (!_isPulsing && _breathCtrl.isAnimating) {
      _breathCtrl.stop();
      _breathCtrl.reset();
    }
  }

  @override
  void dispose() {
    _breathCtrl.dispose();
    super.dispose();
  }

  Widget _detailBlock(String text, Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: accent),
      ),
    );
  }

  Widget _expandedPayload(Color accent) {
    if (_isIngesting) {
      final parseFormat = widget.event['parse_format']?.toString();
      return _detailBlock(
        'Content fetched${parseFormat != null ? " as ${parseFormat.toUpperCase()}" : ""}, summarizing content…',
        accent,
      );
    }
    if (_isError) {
      return _detailBlock(
        widget.event['error']?.toString() ?? 'Tool call failed.',
        accent,
      );
    }

    final payload = widget.event['result_payload'];
    if (payload is! Map) return const SizedBox.shrink();
    final kind = widget.event['kind']?.toString();
    if (kind == 'search') {
      final results = payload['results'];
      if (results is! List || results.isEmpty) {
        return _detailBlock('No displayable search results returned.', accent);
      }
      return Column(
        children: results.whereType<Map>().map((result) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFFD8E5EF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result['title']?.toString() ?? 'Search result',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  result['snippet']?.toString() ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF52606D),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  result['url']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    }
    if (kind == 'fetch') {
      final addedVal = widget.event['new_chunks_added'];
      final stageVal = widget.event['stage']?.toString();
      final parseFormat = widget.event['parse_format']?.toString();
      final isDedup = addedVal is num && addedVal == 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            payload['url']?.toString() ?? widget.event['url']?.toString() ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              if (parseFormat != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (parseFormat == 'pdf' || parseFormat == 'skipped_pdf')
                        ? const Color(0xFFFFF3E0)
                        : const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    parseFormat == 'skipped_pdf'
                        ? 'SKIPPED (PDF)'
                        : parseFormat.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color:
                          (parseFormat == 'pdf' || parseFormat == 'skipped_pdf')
                          ? const Color(0xFFE65100)
                          : const Color(0xFF2E7D32),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (stageVal != null) ...[
                Text(
                  stageVal,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (isDedup)
                const Text(
                  'Already read (cache hit)',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF5C6BC0),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              if (widget.event.containsKey('facts_count') ||
                  widget.event.containsKey('findings_count'))
                Text(
                  '${widget.event['facts_count'] ?? 0} facts · ${widget.event['findings_count'] ?? 0} findings extracted',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF327342),
                  ),
                )
              else if (addedVal is num && addedVal > 0)
                Text(
                  '$addedVal new chunks added',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF327342),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          _detailBlock(payload['content_preview']?.toString() ?? '', accent),
        ],
      );
    }
    return _detailBlock(payload['summary']?.toString() ?? '', accent);
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.event['kind']?.toString();
    final isSearch = kind == 'search';
    final isFetch = kind == 'fetch';
    final isError = _isError;
    final isRunning = _isRunning;
    final isIngesting = _isIngesting;
    final tool = widget.event['tool']?.toString() ?? kind ?? 'tool';
    final toolLabel = isSearch
        ? 'Web search'
        : isFetch
        ? 'Read URL'
        : tool;
    final target = isSearch
        ? widget.event['query']?.toString() ?? 'No query'
        : isFetch
        ? widget.event['url']?.toString() ?? 'No URL'
        : 'Tool: ' + tool;
    final resultCount = widget.event['result_count']?.toString();
    final added = widget.event['new_chunks_added'];
    final addedStr = added?.toString();
    final novelty = widget.event['novelty_ratio'];
    final latencyMs = widget.event['latency_ms'];
    final latency = latencyMs is num
        ? ' · ' + (latencyMs / 1000).toStringAsFixed(1) + 's'
        : '';
    final isDedup =
        (added is num && added == 0) ||
        widget.event['already_attempted'] == true;
    final detail = isRunning
        ? 'Fetching…'
        : isIngesting
        ? 'Summarizing content…'
        : isError
        ? widget.event['error']?.toString() ?? 'Tool call failed'
        : isSearch
        ? (resultCount ?? '0') + ' results'
        : isFetch
        ? isDedup
              ? 'Already read'
              : widget.event.containsKey('facts_count')
              ? '${widget.event['facts_count']} facts · ${widget.event['findings_count']} findings'
              : (addedStr ?? '0') +
                    ' chunks' +
                    (novelty is num
                        ? ' · ' + (novelty * 100).toStringAsFixed(0) + '% novel'
                        : '')
        : tool;
    final background = isError
        ? const Color(0xFFF9ECE8)
        : isRunning
        ? const Color(0xFFEEF2F7)
        : isIngesting
        ? const Color(0xFFFFF8E1)
        : isSearch
        ? const Color(0xFFEAF3FA)
        : isFetch
        ? const Color(0xFFEDF6EF)
        : const Color(0xFFF3F4F6);
    final border = isError
        ? const Color(0xFF9B4D39)
        : isRunning
        ? const Color(0xFFB8C4D4)
        : isIngesting
        ? const Color(0xFFFFCC02)
        : isSearch
        ? const Color(0xFFB8D3E8)
        : isFetch
        ? const Color(0xFFB9D9C0)
        : const Color(0xFFD1D5DB);
    final accent = isError
        ? const Color(0xFF9B4D39)
        : isRunning
        ? const Color(0xFF5A6B7D)
        : isIngesting
        ? const Color(0xFFF57F17)
        : isSearch
        ? const Color(0xFF1D5E85)
        : isFetch
        ? const Color(0xFF327342)
        : const Color(0xFF4B5563);
    final icon = isError
        ? Icons.error_outline
        : isIngesting
        ? Icons.storage_outlined
        : isSearch
        ? Icons.search
        : isFetch
        ? Icons.language
        : Icons.settings;
    final statusIcon = isRunning
        ? Icons.more_horiz
        : isIngesting
        ? Icons.sync
        : isError
        ? Icons.error_outline
        : isDedup && isFetch
        ? Icons.inventory_2_outlined
        : Icons.check_circle;

    return InkWell(
      onTap: _canExpand ? () => setState(() => _expanded = !_expanded) : null,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 450),
        opacity: _isPulsing ? 0.72 + 0.28 * _breathCtrl.value : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 17, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          toolLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          target,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF52606D),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Icon(statusIcon, size: 16, color: accent),
                      if (!isRunning && latency.isNotEmpty)
                        Text(
                          latency.trim(),
                          style: TextStyle(fontSize: 10.5, color: accent),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                maxLines: isError ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: accent),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 180),
                sizeCurve: Curves.easeInOut,
                crossFadeState: _expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _expandedPayload(accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
