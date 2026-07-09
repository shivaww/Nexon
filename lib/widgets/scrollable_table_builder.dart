import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

class ScrollableTableBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        border: TableBorder.all(color: Colors.grey.withOpacity(0.3), width: 1),
        defaultColumnWidth: const IntrinsicColumnWidth(),
        children: element.children!.whereType<md.Element>().expand((child) {
          if (child.tag == 'thead' || child.tag == 'tbody') {
            return child.children!.whereType<md.Element>().map((row) {
              return TableRow(
                children: row.children!.whereType<md.Element>().map((cell) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                    child: RichText(
                      softWrap: false,
                      text: TextSpan(
                        children: cell.children?.map((node) => _parseNode(node, preferredStyle, cell.tag == 'th')).toList() ?? [],
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
    TextStyle baseStyle = style ?? const TextStyle(color: Colors.black);
    if (isHeader) {
      baseStyle = baseStyle.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF2D241C));
    } else {
      baseStyle = baseStyle.copyWith(color: const Color(0xFF1E1E1E), fontSize: 14);
    }

    if (node is md.Text) {
      return TextSpan(text: node.text, style: baseStyle);
    } else if (node is md.Element) {
      TextStyle currentStyle = baseStyle;
      if (node.tag == 'strong') currentStyle = baseStyle.copyWith(fontWeight: FontWeight.bold);
      if (node.tag == 'em') currentStyle = baseStyle.copyWith(fontStyle: FontStyle.italic);
      if (node.tag == 'code') currentStyle = baseStyle.copyWith(fontFamily: 'monospace', backgroundColor: Colors.grey.shade200, color: Colors.black87);
      
      return TextSpan(
        children: node.children?.map((child) => _parseNode(child, currentStyle, false)).toList() ?? [],
        style: currentStyle,
      );
    }
    return const TextSpan();
  }
}
