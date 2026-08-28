// Extracted from main.dart lines 8779-9572
// Extracted on: 2026-08-26T18:20:45.730153

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexon/widgets/liquid_glass_widgets.dart';
import 'package:nexon/main.dart';

class McpToolBlock extends StatefulWidget {
  const McpToolBlock({required this.mcpJson, this.isXml = false, super.key});
  final String mcpJson;
  final bool isXml;

  @override
  State<McpToolBlock> createState() => _McpToolBlockState();
}

class _McpToolBlockState extends State<McpToolBlock> {
  bool _expanded = false;

  /// Returns (icon, label, subtitle) for a method + params.
  (IconData, Color, String, String?) _describe(
    String method,
    Map<String, dynamic> params,
  ) {
    String p(String key) => params[key]?.toString() ?? '';
    String shortPath(String path) {
      if (path.isEmpty) return '';
      final parts = path.split('/');
      return parts.length > 2 ? '…/${parts.last}' : path;
    }

    switch (method) {
      case 'read_file_rich':
      case 'file_read':
        {
          final path = shortPath(p('path'));
          final start = p('start_line');
          final end = p('end_line');
          final sub = (start.isNotEmpty && end.isNotEmpty)
              ? 'lines $start–$end'
              : null;
          return (
            Icons.menu_book_outlined,
            const Color(0xFF0369A1),
            'Read  $path',
            sub,
          );
        }
      case 'multi_read_rich':
      case 'multi_read':
        return (
          Icons.library_books_outlined,
          const Color(0xFF0369A1),
          'Batch read files',
          null,
        );
      case 'patch_file':
      case 'patch_file_rich':
        return (
          Icons.edit_outlined,
          const Color(0xFF7C3AED),
          'Patch  ${shortPath(p('path'))}',
          'search-replace',
        );
      case 'replace_lines':
      case 'replace_lines_rich':
        return (
          Icons.edit_outlined,
          const Color(0xFF7C3AED),
          'Replace lines  ${p('start_line')}–${p('end_line')}',
          shortPath(p('path')),
        );
      case 'insert_lines':
      case 'insert_lines_rich':
        return (
          Icons.playlist_add,
          const Color(0xFF059669),
          'Insert after line ${p('after_line')}',
          shortPath(p('path')),
        );
      case 'delete_lines':
      case 'delete_lines_rich':
        return (
          Icons.delete_sweep_outlined,
          const Color(0xFFDC2626),
          'Delete lines ${p('start_line')}–${p('end_line')}',
          shortPath(p('path')),
        );
      case 'write_file_rich':
      case 'file_write':
        return (
          Icons.edit_document,
          const Color(0xFF059669),
          'Write  ${shortPath(p('path'))}',
          null,
        );
      case 'search_rich':
      case 'file_search':
        return (
          Icons.search,
          const Color(0xFF0369A1),
          'Search files',
          p('query').isNotEmpty
              ? '"${p('query')}"'
              : p('pattern').isNotEmpty
              ? '"${p('pattern')}"'
              : null,
        );
      case 'file_outline':
      case 'file_outline_rich':
        return (
          Icons.account_tree_outlined,
          const Color(0xFF0369A1),
          'Outline  ${shortPath(p('path'))}',
          null,
        );
      case 'tree':
      case 'tree_rich':
        return (
          Icons.folder_open_outlined,
          const Color(0xFFD97706),
          'Tree  ${shortPath(p('path'))}',
          null,
        );
      case 'diff_files':
      case 'diff_files_rich':
        return (
          Icons.difference_outlined,
          const Color(0xFF475569),
          'Diff files',
          null,
        );
      case 'symbol_references':
        return (
          Icons.functions,
          const Color(0xFF7C3AED),
          'References',
          p('symbol'),
        );
      case 'append_file':
        return (
          Icons.note_add_outlined,
          const Color(0xFF059669),
          'Append  ${shortPath(p('path'))}',
          null,
        );
      case 'delete_path':
        return (
          Icons.delete_outline,
          const Color(0xFFDC2626),
          'Delete  ${shortPath(p('path'))}',
          p('recursive') == 'true' ? 'recursive' : null,
        );
      case 'move_path':
        return (
          Icons.drive_file_move_outlined,
          const Color(0xFF475569),
          'Move  ${shortPath(p('src'))}',
          shortPath(p('dest')),
        );
      case 'copy_path':
        return (
          Icons.copy_outlined,
          const Color(0xFF475569),
          'Copy  ${shortPath(p('src'))}',
          shortPath(p('dest')),
        );
      case 'mkdir_path':
        return (
          Icons.create_new_folder_outlined,
          const Color(0xFFD97706),
          'Create dir  ${shortPath(p('path'))}',
          null,
        );
      case 'stat_path':
        return (
          Icons.info_outline,
          const Color(0xFF475569),
          'Stat  ${shortPath(p('path'))}',
          null,
        );
      case 'chmod_path':
        return (
          Icons.lock_outline,
          const Color(0xFF475569),
          'Chmod ${p('mode')}',
          shortPath(p('path')),
        );
      case 'list_trash':
        return (
          Icons.delete_outline,
          const Color(0xFF475569),
          'List trash',
          null,
        );
      case 'restore_trash':
        return (
          Icons.restore_from_trash_outlined,
          const Color(0xFF059669),
          'Restore ${p('name')}',
          shortPath(p('dest')),
        );
      case 'tool_help':
        return (
          Icons.help_outline,
          const Color(0xFF475569),
          'Tool reference',
          null,
        );
      case 'find_files':
        return (
          Icons.manage_search_outlined,
          const Color(0xFFD97706),
          'Find  ${p('pattern')}',
          shortPath(p('path')),
        );
      case 'symbol_search':
        return (
          Icons.travel_explore_outlined,
          const Color(0xFF7C3AED),
          'Symbol search  ${p('symbol')}',
          shortPath(p('path')),
        );
      case 'file_edit':
        {
          final path = shortPath(p('path'));
          final start = p('start_line');
          final end = p('end_line');
          final sub = (start.isNotEmpty && end.isNotEmpty)
              ? 'lines $start–$end'
              : null;
          return (
            Icons.edit_outlined,
            const Color(0xFF7C3AED),
            'Edit  $path',
            sub,
          );
        }
      case 'file_delete':
        return (
          Icons.delete_outline,
          const Color(0xFFDC2626),
          'Delete  ${shortPath(p('path'))}',
          null,
        );
      case 'dir_list':
        return (
          Icons.folder_open_outlined,
          const Color(0xFFD97706),
          'List  ${shortPath(p('path'))}',
          null,
        );
      case 'dir_create':
        return (
          Icons.create_new_folder_outlined,
          const Color(0xFFD97706),
          'Create dir  ${shortPath(p('path'))}',
          null,
        );
      case 'find_paths':
        return (
          Icons.find_in_page_outlined,
          const Color(0xFF0369A1),
          'Find paths',
          p('pattern').isNotEmpty ? '"${p('pattern')}"' : null,
        );
      case 'code_search':
        return (
          Icons.manage_search,
          const Color(0xFF0369A1),
          'Code search',
          '"${p('query')}" in ${shortPath(p('path'))}',
        );
      case 'symbol_search':
        return (
          Icons.functions,
          const Color(0xFF7C3AED),
          'Symbol search',
          p('symbol'),
        );
      case 'file_info':
        return (
          Icons.info_outline,
          const Color(0xFF475569),
          'File info',
          shortPath(p('path')),
        );
      case 'run_command':
      case 'shell_rich':
        {
          final cmd = p('command');
          final short = cmd.length > 55 ? '${cmd.substring(0, 52)}…' : cmd;
          if (cmd.contains('firebase deploy'))
            return (
              Icons.cloud_upload_outlined,
              const Color(0xFFEA4335),
              '🚀 Deploy to Firebase',
              null,
            );
          if (cmd.contains('gh workflow run'))
            return (
              Icons.play_circle_outline,
              const Color(0xFF24292E),
              '⚙️ Trigger GitHub Actions',
              null,
            );
          if (cmd.contains('gh run watch'))
            return (
              Icons.timelapse,
              const Color(0xFF24292E),
              '⏳ Watch Actions build',
              null,
            );
          if (cmd.contains('gh run download'))
            return (
              Icons.download_outlined,
              const Color(0xFF24292E),
              '⬇️ Download artifact',
              null,
            );
          if (cmd.contains('git commit'))
            return (
              Icons.commit,
              const Color(0xFFF05032),
              '📦 Git commit',
              null,
            );
          if (cmd.contains('git push'))
            return (
              Icons.upload_outlined,
              const Color(0xFFF05032),
              '📤 Git push',
              null,
            );
          if (cmd.contains('git status'))
            return (
              Icons.info_outline,
              const Color(0xFFF05032),
              '📊 Git status',
              null,
            );
          if (cmd.contains('git diff'))
            return (
              Icons.difference_outlined,
              const Color(0xFFF05032),
              '🔍 Git diff',
              null,
            );
          if (cmd.contains('flutter build'))
            return (
              Icons.build_outlined,
              const Color(0xFF0175C2),
              '🔨 Flutter build',
              null,
            );
          if (cmd.contains('flutter test'))
            return (
              Icons.science_outlined,
              const Color(0xFF0175C2),
              '🧪 Flutter test',
              null,
            );
          if (cmd.contains('dart analyze'))
            return (
              Icons.analytics_outlined,
              const Color(0xFF0175C2),
              '🧹 Dart analyze',
              null,
            );
          if (cmd.contains('pkg install'))
            return (
              Icons.install_desktop_outlined,
              const Color(0xFF475569),
              '📦 Install package',
              null,
            );
          return (
            Icons.terminal,
            const Color(0xFF1E293B),
            short,
            p('cwd').isNotEmpty ? 'cwd: ${shortPath(p('cwd'))}' : null,
          );
        }
      case 'run_background':
        return (
          Icons.play_circle_outline,
          const Color(0xFF059669),
          'Background service',
          p('command'),
        );
      case 'list_services':
        return (
          Icons.list_alt_outlined,
          const Color(0xFF475569),
          'List services',
          null,
        );
      case 'service_status':
        return (
          Icons.info_outline,
          const Color(0xFF475569),
          'Service status',
          p('id'),
        );
      case 'service_logs':
        return (
          Icons.article_outlined,
          const Color(0xFF475569),
          'Service logs',
          p('id'),
        );
      case 'stop_service':
        return (
          Icons.stop_circle_outlined,
          const Color(0xFFDC2626),
          'Stop service',
          p('id'),
        );
      case 'wait_for_background':
      case 'background_time_limit':
        return (
          Icons.timer_outlined,
          const Color(0xFFD97706),
          'Wait for background job',
          p('pid') ?? p('id'),
        );
      case 'dart_diagnostics':
      case 'dart_analyze':
        return (
          Icons.analytics_outlined,
          const Color(0xFF0175C2),
          'Dart diagnostics',
          shortPath(p('path')),
        );
      case 'dart_format':
        return (
          Icons.format_align_left,
          const Color(0xFF0175C2),
          'Dart format',
          shortPath(p('path')),
        );
      case 'git_status':
        return (
          Icons.info_outline,
          const Color(0xFFF05032),
          'Git status',
          null,
        );
      case 'git_diff':
        return (
          Icons.difference_outlined,
          const Color(0xFFF05032),
          'Git diff',
          null,
        );
      case 'workspace_list':
        return (
          Icons.folder_open_outlined,
          const Color(0xFFD97706),
          'List workspace files',
          null,
        );
      case 'workspace_search':
        {
          final queries = params['queries'];
          String? querySub;
          if (queries is List && queries.isNotEmpty) {
            querySub = queries.map((q) => '"$q"').join(', ');
          } else if (p('query').isNotEmpty) {
            querySub = '"${p('query')}"';
          }
          return (
            Icons.search,
            const Color(0xFF0369A1),
            'Search workspace',
            querySub,
          );
        }
      case 'workspace_ingest':
        return (
          Icons.upload_file,
          const Color(0xFF059669),
          'Ingest  ${shortPath(p('file_path'))}',
          null,
        );
      case 'workspace_read_page':
        return (
          Icons.menu_book_outlined,
          const Color(0xFF0369A1),
          'Read page  ${p('page')}',
          shortPath(p('file_path')),
        );
      case 'workspace_get_outline':
        return (
          Icons.account_tree_outlined,
          const Color(0xFF0369A1),
          'Outline  ${shortPath(p('file_path'))}',
        );
      case 'workspace_cross_compare':
        return (
          Icons.compare_arrows,
          const Color(0xFF7C3AED),
          'Cross-compare',
          p('query').isNotEmpty ? '"${p('query')}"' : null,
        );
      // ── Native C++ bridge tools (JSON {"t","a"} format) ─────────────
      case 'read':
        {
          final r = params['r'];
          final firstF = (r is List && r.isNotEmpty && r.first is Map)
              ? shortPath((r.first as Map)['f']?.toString() ?? '')
              : null;
          return (
            Icons.menu_book_outlined,
            const Color(0xFF0369A1),
            'Read${r is List && r.length > 1 ? ' ${r.length} ranges' : ''}',
            firstF,
          );
        }
      case 'search':
        {
          final q = params['q'];
          final sub = (q is List && q.isNotEmpty)
              ? '"${q.first}"'
              : (p('q').isNotEmpty ? '"${p('q')}"' : null);
          return (Icons.search, const Color(0xFF0369A1), 'Search', sub);
        }
      case 'patch':
        {
          final ps = params['p'];
          final firstF = (ps is List && ps.isNotEmpty && ps.first is Map)
              ? shortPath((ps.first as Map)['f']?.toString() ?? '')
              : null;
          return (
            Icons.edit_outlined,
            const Color(0xFF7C3AED),
            'Patch${ps is List && ps.length > 1 ? ' ${ps.length} edits' : ''}',
            firstF,
          );
        }
      case 'edit':
        return (
          Icons.edit_outlined,
          const Color(0xFF7C3AED),
          'Edit',
          p('f').isNotEmpty ? shortPath(p('f')) : null,
        );
      case 'create_file':
        return (Icons.edit_document, const Color(0xFF059669), 'Create file', shortPath(p('f')));
      case 'create_directory':
        return (Icons.create_new_folder_outlined, const Color(0xFFD97706), 'Create dir', shortPath(p('p')));
      case 'list':
        return (Icons.folder_open_outlined, const Color(0xFFD97706), 'List', shortPath(p('p')));
      case 'find':
        return (Icons.manage_search_outlined, const Color(0xFFD97706), 'Find', p('glob').isNotEmpty ? '"${p('glob')}"' : null);
      case 'outline':
        return (Icons.account_tree_outlined, const Color(0xFF0369A1), 'Outline', shortPath(p('f')));
      case 'recent':
        return (Icons.history, const Color(0xFF475569), 'Recent files', null);
      case 'undo':
        return (Icons.restore_from_trash_outlined, const Color(0xFF059669), 'Undo', shortPath(p('f')));
      case 'git':
        return (Icons.commit, const Color(0xFFF05032), 'Git ${p('a')}', null);
      case 'sh':
        {
          final cmd = p('cmd');
          final short = cmd.length > 55 ? '${cmd.substring(0, 52)}…' : cmd;
          return (Icons.terminal, const Color(0xFF1E293B), 'Run', short.isNotEmpty ? short : null);
        }
      case 'fileops':
        {
          final ops = params['ops'];
          return (Icons.folder_copy_outlined, const Color(0xFF475569), 'File ops${ops is List ? ' (${ops.length})' : ''}', null);
        }
      case 'cut':
      case 'extract':
        return (Icons.content_cut, const Color(0xFF7C3AED), method == 'cut' ? 'Split' : 'Extract', shortPath(p('f')));
      case 'diagnostics':
        return (Icons.analytics_outlined, const Color(0xFF0175C2), 'Diagnostics', p('cmd').isNotEmpty ? p('cmd') : null);
      case 'py':
        return (Icons.code, const Color(0xFF0175C2), 'Python', p('m').isNotEmpty ? p('m') : null);
      case 'web_search':
        {
          final qList = params['queries'] ?? params['q_list'];
          if (qList is List && qList.isNotEmpty) {
            final labels = qList.take(4).map((q) => '"$q"').join(' + ');
            return (Icons.search, const Color(0xFF0369A1), 'Web search (${qList.length})', labels);
          }
          final q = p('q');
          return (Icons.search, const Color(0xFF0369A1), 'Web search', q.isNotEmpty ? '"$q"' : (p('query').isNotEmpty ? '"${p('query')}"' : null));
        }
      case 'read_url':
        return (Icons.link, const Color(0xFF0369A1), 'Read webpage', p('url').isNotEmpty ? shortPath(p('url')) : null);
      case 'todo_create':
        {
          final tasks = params['tasks'];
          final count = tasks is List ? tasks.length : 0;
          return (Icons.checklist, const Color(0xFF7C3AED), 'Plan ($count)', count > 0 ? '$count tasks' : null);
        }
      case 'todo_done':
        {
          final n = p('n');
          return (Icons.check_circle, const Color(0xFF059669), 'Task done', n.isNotEmpty ? '#$n' : null);
        }
      case 'quiz':
        return (Icons.school_outlined, const Color(0xFFD97706), 'Quiz', null);
      default:
        return (
          Icons.build_circle_outlined,
          const Color(0xFF2B6CB0),
          method,
          null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    String method = 'unknown';
    Map<String, dynamic> params = {};
    String formattedContent = widget.mcpJson;

    if (widget.isXml) {
      final methodMatch = RegExp(
        r'<method[^>]*?>([\s\S]*?)</method\s*>',
        caseSensitive: false,
      ).firstMatch(widget.mcpJson);
      if (methodMatch != null) {
        method = methodMatch.group(1)?.trim() ?? method;
      }

      // Parse XML params for description (direct tags)
      final regex = RegExp(
        r'<([a-zA-Z0-9_]+)(?:\s+[^>]*?)?>([\s\S]*?)</\1\s*>',
        caseSensitive: false,
      );
      for (final match in regex.allMatches(widget.mcpJson)) {
        final key = match.group(1)!.toLowerCase();
        if (key != 'method') {
          params[key] = match.group(2)?.trim() ?? '';
        }
      }

      // Fallback: <PARAM name="key">value</PARAM>
      final paramRegex = RegExp(
        r'''<[Pp][Aa][Rr][Aa][Mm]\s+name=["']([a-zA-Z0-9_]+)["']\s*>([\s\S]*?)</[Pp][Aa][Rr][Aa][Mm]>''',
      );
      for (final m in paramRegex.allMatches(widget.mcpJson)) {
        final key = m.group(1)!.toLowerCase();
        if (key != 'method') {
          params[key] = m.group(2)?.trim() ?? '';
        }
      }

      // Fallback: <parameter name="key">value</parameter>
      final paramRegex2 = RegExp(
        r'''<[Pp]arameter\s+name=["']([a-zA-Z0-9_]+)["']\s*>([\s\S]*?)</[Pp]arameter>''',
        caseSensitive: false,
      );
      for (final m in paramRegex2.allMatches(widget.mcpJson)) {
        final key = m.group(1)!.toLowerCase();
        if (key != 'method') {
          params[key] = m.group(2)?.trim() ?? '';
        }
      }
      formattedContent = widget.mcpJson.trim();
    } else {
      try {
        final decoded = jsonDecode(widget.mcpJson) as Map<String, dynamic>;
        method = decoded['method']?.toString() ?? method;
        params = (decoded['params'] as Map<String, dynamic>?) ?? {};
        formattedContent = const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {}
    }

    final (icon, color, label, subtitle) = _describe(method, params);

    return LiquidGlassSurface(
      margin: const EdgeInsets.symmetric(vertical: 8),
      borderRadius: BorderRadius.circular(14),
      backgroundColor: color.withValues(alpha: 0.12),
      highlightColor: color.withValues(alpha: 0.50),
      shadowColor: color.withValues(alpha: 0.20),
      enableBlur: false, // Optimized for scrolling list performance
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 17, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: color,
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 11,
                              color: color.withValues(alpha: 0.75),
                              fontFamily: 'monospace',
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: color.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                formattedContent,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  color: Color(0xFFCDD6F4),
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PermissionInfoRow extends StatelessWidget {
  const PermissionInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7EC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE7D8C4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8A7765),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            value,
            style: const TextStyle(
              color: Color(0xFF2D241C),
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}
