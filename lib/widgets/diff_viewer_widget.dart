import 'package:flutter/material.dart';

class DiffViewerWidget extends StatelessWidget {
  final String content;

  const DiffViewerWidget({Key? key, required this.content}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final rows = _parseUnifiedDiff(content);
    final added = rows.where((row) => row.kind == _DiffKind.added).length;
    final removed = rows.where((row) => row.kind == _DiffKind.removed).length;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF6),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: const Color(0xFFE7D8C4)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              color: const Color(0xFFF4E9D9),
              child: Row(
                children: [
                  const Icon(
                    Icons.difference_outlined,
                    size: 15,
                    color: Color(0xFF6C4A2F),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'File changes',
                      style: TextStyle(
                        color: Color(0xFF2D241C),
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  _CountPill(label: '+$added', color: const Color(0xFF137333)),
                  const SizedBox(width: 6),
                  _CountPill(
                    label: '-$removed',
                    color: const Color(0xFFB3261E),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 360),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: rows.map((row) => _DiffRowView(row: row)).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_DiffRow> _parseUnifiedDiff(String diff) {
    final rows = <_DiffRow>[];
    int? oldLine;
    int? newLine;
    final hunkRegex = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@');

    for (final raw in diff.split('\n')) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      final hunk = hunkRegex.firstMatch(line);
      if (hunk != null) {
        oldLine = int.tryParse(hunk.group(1) ?? '');
        newLine = int.tryParse(hunk.group(2) ?? '');
        rows.add(_DiffRow(kind: _DiffKind.hunk, text: line));
        continue;
      }

      if (line.startsWith('+++') || line.startsWith('---')) {
        rows.add(_DiffRow(kind: _DiffKind.file, text: line));
        continue;
      }

      if (line.startsWith('+')) {
        rows.add(_DiffRow(kind: _DiffKind.added, newLine: newLine, text: line));
        if (newLine != null) newLine++;
      } else if (line.startsWith('-')) {
        rows.add(
          _DiffRow(kind: _DiffKind.removed, oldLine: oldLine, text: line),
        );
        if (oldLine != null) oldLine++;
      } else if (line.startsWith(' ')) {
        rows.add(
          _DiffRow(
            kind: _DiffKind.context,
            oldLine: oldLine,
            newLine: newLine,
            text: line,
          ),
        );
        if (oldLine != null) oldLine++;
        if (newLine != null) newLine++;
      } else if (line.trim().isNotEmpty) {
        rows.add(_DiffRow(kind: _DiffKind.file, text: line));
      }
    }
    return rows;
  }
}

enum _DiffKind { added, removed, context, hunk, file }

class _DiffRow {
  const _DiffRow({
    required this.kind,
    required this.text,
    this.oldLine,
    this.newLine,
  });

  final _DiffKind kind;
  final int? oldLine;
  final int? newLine;
  final String text;
}

class _DiffRowView extends StatelessWidget {
  const _DiffRowView({required this.row});

  final _DiffRow row;

  @override
  Widget build(BuildContext context) {
    final isAdded = row.kind == _DiffKind.added;
    final isRemoved = row.kind == _DiffKind.removed;
    final isHunk = row.kind == _DiffKind.hunk;
    final isFile = row.kind == _DiffKind.file;
    final bg = isAdded
        ? const Color(0xFFE8F5E9)
        : isRemoved
        ? const Color(0xFFFFEDEA)
        : isHunk
        ? const Color(0xFFEAF1FB)
        : isFile
        ? const Color(0xFFF4E9D9)
        : const Color(0xFFFFFCF6);
    final fg = isAdded
        ? const Color(0xFF137333)
        : isRemoved
        ? const Color(0xFFB3261E)
        : isHunk
        ? const Color(0xFF2459A6)
        : const Color(0xFF2D241C);

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LineNumber(value: row.oldLine),
          _LineNumber(value: row.newLine),
          const SizedBox(width: 8),
          SizedBox(
            width: 18,
            child: Text(
              isAdded
                  ? '+'
                  : isRemoved
                  ? '-'
                  : '',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ),
          Text(
            row.text.isNotEmpty &&
                    (row.text.startsWith('+') ||
                        row.text.startsWith('-') ||
                        row.text.startsWith(' '))
                ? row.text.substring(1)
                : row.text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.35,
              color: fg,
              fontWeight: isHunk || isFile ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineNumber extends StatelessWidget {
  const _LineNumber({this.value});

  final int? value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      child: Text(
        value?.toString() ?? '',
        textAlign: TextAlign.right,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: Color(0xFF9B8A78),
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
