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
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      cell.textContent,
                      style: preferredStyle?.copyWith(
                        fontWeight: cell.tag == 'th' ? FontWeight.bold : FontWeight.normal,
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
}
