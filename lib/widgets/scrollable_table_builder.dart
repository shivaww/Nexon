import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

class ScrollableTableBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final rows = <TableRow>[];

    for (final child in element.children!.whereType<md.Element>()) {
      if (child.tag == 'thead' || child.tag == 'tbody') {
        final isHeaderSection = child.tag == 'thead';
        for (final row in child.children!.whereType<md.Element>()) {
          final cells = <Widget>[];
          for (final cell in row.children!.whereType<md.Element>()) {
            final isHeader = cell.tag == 'th' || isHeaderSection;
            cells.add(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                constraints: const BoxConstraints(
                  minWidth: 140.0,
                  maxWidth: 380.0,
                ),
                child: SelectableText.rich(
                  TextSpan(
                    children: cell.children
                            ?.map((node) => _parseNode(node, preferredStyle, isHeader))
                            .toList() ??
                        [],
                  ),
                ),
              ),
            );
          }
          rows.add(
            TableRow(
              decoration: isHeaderSection
                  ? const BoxDecoration(
                      color: Color(0xFFF1F5F9),
                    )
                  : const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE2E8F0), width: 0.8),
                      ),
                    ),
              children: cells,
            ),
          );
        }
      }
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return ScrollableTableWrapper(
      child: IntrinsicWidth(
        child: Table(
          border: TableBorder.all(
            color: const Color(0xFFCBD5E1),
            width: 1.0,
          ),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: rows,
        ),
      ),
    );
  }

  InlineSpan _parseNode(md.Node node, TextStyle? style, bool isHeader) {
    TextStyle baseStyle = style ?? const TextStyle(fontFamily: 'Manrope');
    if (isHeader) {
      baseStyle = baseStyle.copyWith(
        fontWeight: FontWeight.bold,
        color: const Color(0xFF0F172A),
        fontSize: 13.5,
        fontFamily: baseStyle.fontFamily ?? 'Manrope',
      );
    } else {
      baseStyle = baseStyle.copyWith(
        color: const Color(0xFF334155),
        fontSize: 13.0,
        fontFamily: baseStyle.fontFamily ?? 'Manrope',
      );
    }

    if (node is md.Text) {
      return TextSpan(text: node.text, style: baseStyle);
    } else if (node is md.Element) {
      TextStyle currentStyle = baseStyle;
      if (node.tag == 'strong') currentStyle = baseStyle.copyWith(fontWeight: FontWeight.bold);
      if (node.tag == 'em') currentStyle = baseStyle.copyWith(fontStyle: FontStyle.italic);
      if (node.tag == 'code') {
        currentStyle = baseStyle.copyWith(
          fontFamily: 'monospace',
          backgroundColor: const Color(0xFFF1F5F9),
          color: const Color(0xFF0F172A),
        );
      }

      return TextSpan(
        children: node.children?.map((child) => _parseNode(child, currentStyle, false)).toList() ?? [],
        style: currentStyle,
      );
    }
    return const TextSpan();
  }
}

class ScrollableTableWrapper extends StatefulWidget {
  final Widget child;
  const ScrollableTableWrapper({required this.child, super.key});

  @override
  State<ScrollableTableWrapper> createState() => _ScrollableTableWrapperState();
}

class _ScrollableTableWrapperState extends State<ScrollableTableWrapper> {
  final ScrollController _scrollController = ScrollController();
  bool _showRightIndicator = false;
  bool _showLeftIndicator = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateIndicators());
    _scrollController.addListener(_updateIndicators);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateIndicators);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateIndicators() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final showRight = maxScroll > 1.0 && currentScroll < maxScroll - 4;
    final showLeft = currentScroll > 4;
    if (showRight != _showRightIndicator || showLeft != _showLeftIndicator) {
      setState(() {
        _showRightIndicator = showRight;
        _showLeftIndicator = showLeft;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _updateIndicators());
          return ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
                PointerDeviceKind.stylus,
              },
            ),
            child: Stack(
              children: [
                SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: widget.child,
                ),
                if (_showLeftIndicator)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 20,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withOpacity(0.12),
                              Colors.transparent,
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_showRightIndicator)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: 28,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.14),
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                        child: const Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: EdgeInsets.only(right: 2.0),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
