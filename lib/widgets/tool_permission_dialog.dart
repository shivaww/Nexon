import 'package:flutter/material.dart';

/// Codex/Claude Code-style approval dialog for patch and edit tool calls.
/// Lists the exact - / + line changes the call will make so the user can
/// review exactly what will change before granting permission.
Future<bool> showToolPermissionDialog(
  BuildContext context,
  String toolName,
  Map<String, dynamic> args,
) async {
  final files = <String>[];
  final lines = <List<Object>>[];
  void addAll(String? text, bool plus) {
    if (text == null) return;
    for (final l in text.split('\n')) {
      lines.add([plus, l]);
    }
  }

  if (toolName == 'patch' && args['p'] is List) {
    for (final e in (args['p'] as List).whereType<Map<String, dynamic>>()) {
      final f = e['f']?.toString() ?? '';
      if (f.isNotEmpty && !files.contains(f)) files.add(f);
      if (e['o'] is String || e['n'] is String) {
        addAll(e['o'] as String?, false);
        addAll(e['n'] as String?, true);
      } else if (e['diff'] is String) {
        for (final l in (e['diff'] as String).split('\n')) {
          if (l.startsWith('+')) {
            lines.add([true, l.substring(1)]);
          } else if (l.startsWith('-')) {
            lines.add([false, l.substring(1)]);
          }
        }
      } else if (e['mode'] == 'replace_lines' || e['mode'] == 'delete_lines') {
        lines.add([false, '(current lines ${e['s']}-${e['e']})']);
        addAll(e['n'] as String?, true);
      }
    }
  } else if (toolName == 'edit' && args['e'] is List) {
    for (final e in (args['e'] as List).whereType<Map<String, dynamic>>()) {
      final f = e['f']?.toString() ?? '';
      if (f.isNotEmpty && !files.contains(f)) files.add(f);
      if (e['mode']?.toString() == 'delete') {
        lines.add([false, '(lines ${e['s']}-${e['e']} of $f)']);
      } else {
        addAll(e['c'] as String?, true);
      }
    }
  }
  final total = lines.length;
  final shown = total > 80 ? lines.sublist(0, 80) : lines;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFFFBF9F4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        const Icon(Icons.shield_outlined, size: 20, color: Color(0xFF7C3AED)),
        const SizedBox(width: 8),
        Expanded(child: Text('Allow $toolName?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D241C)))),
      ]),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(files.join(', '), style: const TextStyle(fontSize: 12, color: Color(0xFF6C5946))),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFF5EFE4), borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  for (final l in shown)
                    Text('${l[0] == true ? '+' : '-'} ${l[1]}', style: TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: l[0] == true ? const Color(0xFF047857) : const Color(0xFFB91C1C))),
                  if (total > shown.length)
                    Text('… ${total - shown.length} more lines', style: const TextStyle(fontSize: 11, color: Color(0xFF8B7355))),
                ]),
              ),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Deny', style: TextStyle(color: Color(0xFFB91C1C)))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Allow')),
      ],
    ),
  );
  return result == true;
}
