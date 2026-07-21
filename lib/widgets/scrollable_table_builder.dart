import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

class ScrollableTableBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return ScrollableTableWrapper(
      child: Table(
        border: TableBorder.all(color: const Color(0xFFE2E8F0), width: 1),
        defaultColumnWidth: const IntrinsicColumnWidth(),
        children: element.children!.whereType<md.Element>().expand((child) {
          if (child.tag == 'thead' || child.tag == 'tbody') {
            final isHeaderSection = child.tag == 'thead';
            return child.children!.whereType<md.Element>().map((row) {
              return TableRow(
                decoration: isHeaderSection
                    ? const BoxDecoration(
                        color: Color(0xFFF8FAFC), // soft slate background for headers
                      )
                    : null,
                children: row.children!.whereType<md.Element>().map((cell) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 95,  // Reasonable min column width
                        // maxWidth: 320, // Commented out to allow intrinsic width
                      ),
                      child: RichText(
                        softWrap: false, // Set to false so IntrinsicColumnWidth can calculate width correctly
                        text: TextSpan(
                          children: cell.children?.map((node) => _parseNode(node, preferredStyle, cell.tag == 'th')).toList() ?? [],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            });
          }
          return <TableRow>[];
        }).toList(),
      ),
    );
  }

  InlineSpan _parseNode(md.Node node, TextStyle? style, bool isHeader) {
    TextStyle baseStyle = style ?? const TextStyle(fontFamily: 'Manrope');
    if (isHeader) {
      baseStyle = baseStyle.copyWith(
        fontWeight: FontWeight.bold,
        color: const Color(0xFF1E293B),
        fontSize: 14,
        fontFamily: baseStyle.fontFamily ?? 'Manrope',
      );
    } else {
      baseStyle = baseStyle.copyWith(
        color: const Color(0xFF334155),
        fontSize: 13.5,
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
    final showRight = maxScroll > 0 && currentScroll < maxScroll - 4;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _updateIndicators());
        return Stack(
          children: [
            SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: widget.child,
            ),
            if (_showLeftIndicator)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 16,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.06),
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
                width: 20,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.08),
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
                          Icons.chevron_right,
                          size: 14,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
