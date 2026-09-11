import 'package:flutter/material.dart';
import 'package:nexon/widgets/liquid_glass_widgets.dart';

/// Canonical tool-call card for every agentic tool, web search,
/// workspace/study result, and tool-result turn.
/// Collapsed: quiet inline status row (icon + one-line summary + chevron).
/// Expanded: warm card revealing the raw detail (args, paths, results).
class ToolCallCard extends StatefulWidget {
  const ToolCallCard({
    required this.icon,
    required this.accent,
    required this.summary,
    required this.detail,
    this.initiallyExpanded = false,
    super.key,
  });

  final IconData icon;
  final Color accent;
  final String summary;
  final Widget detail;
  final bool initiallyExpanded;

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  late bool _expanded = widget.initiallyExpanded;

  Widget _headerRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(widget.icon, size: 15, color: widget.accent),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            widget.summary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6C5946),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          size: 16,
          color: const Color(0xFF8B7355).withValues(alpha: 0.7),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: InkWell(
          onTap: () => setState(() => _expanded = true),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
            child: _headerRow(),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LiquidGlassSurface(
        borderRadius: BorderRadius.circular(14),
        backgroundColor: const Color(0xFFFFFBF2).withValues(alpha: 0.9),
        highlightColor: widget.accent.withValues(alpha: 0.35),
        shadowColor: widget.accent.withValues(alpha: 0.12),
        enableBlur: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = false),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: _headerRow(),
              ),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5EFE4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE7D8C4)),
              ),
              child: widget.detail,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared text style for raw dumps inside a [ToolCallCard] detail panel.
const TextStyle toolCardMonoStyle = TextStyle(
  fontSize: 11.5,
  fontFamily: 'monospace',
  color: Color(0xFF4A3424),
  height: 1.5,
);
