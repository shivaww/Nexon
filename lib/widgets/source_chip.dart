import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// Matches "[Source: file.pdf, Page 3]" (also "Pages 3-4"; first page is used).
class SourceChipSyntax extends md.InlineSyntax {
  SourceChipSyntax()
      : super(r'\[Source:\s*([^\]\n]+?),\s*Pages?\s*(\d+)[^\]\n]*\]');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = md.Element.text('source', match.group(0)!);
    el.attributes['file'] = match.group(1)!.trim();
    el.attributes['page'] = match.group(2)!;
    parser.addNode(el);
    return true;
  }
}

/// Renders a source citation as a tappable chip.
class SourceChipBuilder extends MarkdownElementBuilder {
  SourceChipBuilder({this.onTap});

  final void Function(String file, int page)? onTap;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final file = element.attributes['file'] ?? '';
    final page = int.tryParse(element.attributes['page'] ?? '') ?? 1;
    const accent = Color(0xFF7B4E2E);
    return GestureDetector(
      onTap: onTap == null ? null : () => onTap!(file, page),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description_outlined, size: 12, color: accent),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '$file · p.$page',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
