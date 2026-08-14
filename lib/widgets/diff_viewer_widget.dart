import 'package:flutter/material.dart';

/// IMPROVEMENT: rows are parsed once per content change (not on every build)
/// and rendering is capped at [_kRowCap] rows with an explicit expand toggle,
/// so large diffs no longer build thousands of widgets inside the chat list.
const int _kRowCap = 120;

/// Kind of a parsed unified-diff row.
enum DiffLineKind { added, removed, context, hunk, file }

/// A single parsed row of a unified diff.
///
/// IMPROVEMENT: public + pure so unit tests can cover the parsing logic
/// directly (previously private inside the widget state).
class DiffLine {
  const DiffLine({
    required this.kind,
    required this.text,
    this.oldLine,
    this.newLine,
  });

  final DiffLineKind kind;
  final String text;
  final int? oldLine;
  final int? newLine;
}

/// Parses a unified diff into [DiffLine] rows with old/new line numbers.
///
/// Pure function, safe to call from tests and from the widget state.
List<DiffLine> parseUnifiedDiff(String diff) {
  final rows = <DiffLine>[];
  int? oldLine;
  int? newLine;
  final hunkRegex = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@');

  for (final raw in diff.split('\n')) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    final hunk = hunkRegex.firstMatch(line);
    if (hunk != null) {
      oldLine = int.tryParse(hunk.group(1) ?? '');
      newLine = int.tryParse(hunk.group(2) ?? '');
      rows.add(DiffLine(kind: DiffLineKind.hunk, text: line));
      continue;
    }

    if (line.startsWith('+++') || line.startsWith('---')) {
      rows.add(DiffLine(kind: DiffLineKind.file, text: line));
      continue;
    }

    if (line.startsWith('+')) {
      rows.add(DiffLine(kind: DiffLineKind.added, newLine: newLine, text: line));
      if (newLine != null) newLine++;
    } else if (line.startsWith('-')) {
      rows.add(DiffLine(kind: DiffLineKind.removed, oldLine: oldLine, text: line));
      if (oldLine != null) oldLine++;
    } else if (line.startsWith(' ')) {
      rows.add(
        DiffLine(
          kind: DiffLineKind.context,
          oldLine: oldLine,
          newLine: newLine,
          text: line,
        ),
      );
      if (oldLine != null) oldLine++;
      if (newLine != null) newLine++;
    } else if (line.trim().isNotEmpty) {
      rows.add(DiffLine(kind: DiffLineKind.file, text: line));
    }
  }
  return rows;
}

class DiffViewerWidget extends StatefulWidget {
  final String content;

  const DiffViewerWidget({Key? key, required this.content}) : super(key: key);

  @override
  State<DiffViewerWidget> createState() => _DiffViewerWidgetState();
}

class _DiffViewerWidgetState extends State<DiffViewerWidget> {
  List<DiffLine> _rows = const <DiffLine>[];
  int _added = 0;
  int _removed = 0;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _reparse();
  }

  @override
  void didUpdateWidget(covariant DiffViewerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _expanded = false;
      _reparse();
    }
  }

  void _reparse() {
    final rows = parseUnifiedDiff(widget.content);
    var added = 0;
    var removed = 0;
    for (final row in rows) {
      if (row.kind == DiffLineKind.added) {
        added++;
      } else if (row.kind == DiffLineKind.removed) {
        removed++;
      }
    }
    _rows = rows;
    _added = added;
    _removed = removed;
  }

  @override
  Widget build(BuildContext context) {
    final capped = !_expanded && _rows.length > _kRowCap;
    final visible = capped ? _rows.sublist(0, _kRowCap) : _rows;
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
                  _CountPill(label: '+$_added', color: const Color(0xFF137333)),
                  const SizedBox(width: 6),
                  _CountPill(label: '-$_removed', color: const Color(0xFFB3261E)),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 360),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final row in visible) _DiffRowView(row: row),
                    if (capped)
                      GestureDetector(
                        onTap: () => setState(() => _expanded = true),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          color: const Color(0xFFF4E9D9),
                          child: Text(
                            '… ${_rows.length - _kRowCap} more lines — tap to show all',
                            style: const TextStyle(
                              color: Color(0xFF6C4A2F),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    else if (_expanded && _rows.length > _kRowCap)
                      GestureDetector(
                        onTap: () => setState(() => _expanded = false),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          color: const Color(0xFFF4E9D9),
                          child: const Text(
                            'Collapse',
                            style: TextStyle(
                              color: Color(0xFF6C4A2F),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffRowView extends StatelessWidget {
  const _DiffRowView({required this.row});

  final DiffLine row;

  @override
  Widget build(BuildContext context) {
    final isAdded = row.kind == DiffLineKind.added;
    final isRemoved = row.kind == DiffLineKind.removed;
    final isHunk = row.kind == DiffLineKind.hunk;
    final isFile = row.kind == DiffLineKind.file;
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
              isAdded ? '+' : isRemoved ? '-' : '',
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
