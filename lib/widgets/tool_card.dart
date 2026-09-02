import 'package:flutter/material.dart';
import 'package:nexon/widgets/liquid_glass_widgets.dart';

/// Canonical tool-call card for every agentic tool, web search,
/// workspace/study result, and tool-result turn.
/// Collapsed: compact capsule — icon + one-line summary + chevron.
/// Expanded: raw detail (args, paths, results) in a warm panel.
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: LiquidGlassSurface(
            borderRadius: BorderRadius.circular(14),
            backgroundColor: const Color(0xFFFFFBF2).withValues(alpha: 0.9),
            highlightColor: widget.accent.withValues(alpha: 0.35),
            shadowColor: widget.accent.withValues(alpha: 0.12),
            enableBlur: false, // Optimized for scrolling list performance
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.icon, size: 16, color: widget.accent),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            widget.summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2D241C),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 17,
                          color: const Color(
                            0xFF7B4E2E,
                          ).withValues(alpha: 0.6),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_expanded)
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
