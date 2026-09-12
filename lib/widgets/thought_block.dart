// Extracted from main.dart lines 8677-8777
// Extracted on: 2026-08-26T18:20:45.732356

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexon/widgets/tool_card.dart';

String formatMathText(String text) {
  var formatted = text;

  // Replace double dollar sign math blocks with markdown code block
  final blockMathRegex = RegExp(r'\$\$(.*?)\$\$', dotAll: true);
  formatted = formatted.replaceAllMapped(blockMathRegex, (match) {
    final eq = match.group(1)?.trim() ?? '';
    return '\n```math\n$eq\n```\n';
  });

  // Replace \[ ... \] with code blocks
  final bracketMathRegex = RegExp(r'\\\[(.*?)\\\]', dotAll: true);
  formatted = formatted.replaceAllMapped(bracketMathRegex, (match) {
    final eq = match.group(1)?.trim() ?? '';
    return '\n```math\n$eq\n```\n';
  });

  // Replace \( ... \) with inline code blocks
  final parenMathRegex = RegExp(r'\\\((.*?)\\\)', dotAll: true);
  formatted = formatted.replaceAllMapped(parenMathRegex, (match) {
    final eq = match.group(1)?.trim() ?? '';
    return ' `$eq` ';
  });

  return formatted;
}

/// One timeline row inside the Thought Process disclosure: a thinking
/// bullet or a folded tool call with its result.
class ThoughtEntry {
  const ThoughtEntry({
    required this.icon,
    required this.accent,
    required this.summary,
    required this.detail,
  });

  final IconData icon;
  final Color accent;
  final String summary;
  final Widget detail;
}

class ThoughtBlock extends StatefulWidget {
  const ThoughtBlock({
    this.entries = const [],
    this.active = false,
    super.key,
  });

  /// Timeline rows — thinking bullets and folded tool calls with their
  /// results — rendered in order inside this disclosure.
  final List<ThoughtEntry> entries;

  /// True while this assistant turn is still running. The block opens itself
  /// and stays open for the whole tool loop (call → result → re-think), then
  /// hands control back to the user once the turn finishes.
  final bool active;

  @override
  State<ThoughtBlock> createState() => _ThoughtBlockState();
}

class _ThoughtBlockState extends State<ThoughtBlock> {
  late bool _expanded = widget.active;
  bool _userToggled = false;

  @override
  void didUpdateWidget(covariant ThoughtBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow the turn's active state until the user takes manual control, so
    // a tool loop reopening the block never fights a deliberate collapse.
    if (!_userToggled && widget.active != oldWidget.active) {
      _expanded = widget.active;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2E8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCCBB8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() {
              _expanded = !_expanded;
              _userToggled = true;
            }),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.psychology_outlined,
                    size: 18,
                    color: Color(0xFF7B4E2E),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Thought Process',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6C5946),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: const Color(0xFF6C5946),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in widget.entries)
                    ToolCallCard(
                      icon: entry.icon,
                      accent: entry.accent,
                      summary: entry.summary,
                      detail: entry.detail,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
