// Extracted from main.dart lines 9574-10010
// Extracted on: 2026-08-26T18:20:45.727866

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nexon/main.dart';

TextSpan _highlightCode(String code, String language) {
  final lang = language.toLowerCase();

  final List<String> keywords;
  if (lang == 'python' || lang == 'py') {
    keywords = [
      'def',
      'class',
      'import',
      'from',
      'as',
      'return',
      'if',
      'elif',
      'else',
      'for',
      'while',
      'in',
      'is',
      'not',
      'and',
      'or',
      'try',
      'except',
      'finally',
      'pass',
      'lambda',
      'with',
      'assert',
      'global',
      'nonlocal',
      'del',
      'yield',
      'None',
      'True',
      'False',
    ];
  } else if (lang == 'dart' ||
      lang == 'java' ||
      lang == 'kotlin' ||
      lang == 'go' ||
      lang == 'rust' ||
      lang == 'rs') {
    keywords = [
      'class',
      'import',
      'package',
      'void',
      'return',
      'if',
      'else',
      'for',
      'while',
      'in',
      'try',
      'catch',
      'finally',
      'final',
      'const',
      'var',
      'let',
      'static',
      'extends',
      'implements',
      'interface',
      'mixin',
      'with',
      'as',
      'is',
      'new',
      'this',
      'super',
      'switch',
      'case',
      'default',
      'break',
      'continue',
      'async',
      'await',
      'yield',
      'fn',
      'pub',
      'use',
      'impl',
      'struct',
      'enum',
      'mut',
      'let',
    ];
  } else if (lang == 'javascript' ||
      lang == 'js' ||
      lang == 'typescript' ||
      lang == 'ts') {
    keywords = [
      'class',
      'import',
      'export',
      'from',
      'function',
      'return',
      'if',
      'else',
      'for',
      'while',
      'in',
      'of',
      'try',
      'catch',
      'finally',
      'const',
      'let',
      'var',
      'new',
      'this',
      'super',
      'switch',
      'case',
      'default',
      'break',
      'continue',
      'async',
      'await',
      'yield',
      'type',
      'interface',
      'namespace',
      'typeof',
      'instanceof',
      'true',
      'false',
      'null',
      'undefined',
    ];
  } else {
    keywords = [
      'class',
      'import',
      'export',
      'void',
      'function',
      'return',
      'if',
      'else',
      'for',
      'while',
      'try',
      'catch',
      'finally',
      'const',
      'let',
      'var',
      'final',
      'def',
      'fn',
      'true',
      'false',
      'null',
    ];
  }

  final keywordSet = keywords.toSet();

  // Regex tokenization groups:
  // 1. Block comments
  // 2. Line comments
  // 3. Strings (double, single, or backtick quotes)
  // 4. Numbers
  // 5. Identifiers/Words
  final pattern = RegExp(
    r'''(/\*[\s\S]*?\*/)|(//.*|#.*)|("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`)|(\b\d+(?:\.\d+)?\b)|(\b[a-zA-Z_][a-zA-Z0-9_]*\b)|([\s\S])''',
  );

  final spans = <TextSpan>[];
  final matches = pattern.allMatches(code);

  for (final m in matches) {
    final text = m.group(0)!;
    if (m.group(1) != null || m.group(2) != null) {
      // Comments
      spans.add(
        TextSpan(
          text: text,
          style: const TextStyle(color: Color(0xFF7A828F)),
        ),
      );
    } else if (m.group(3) != null) {
      // Strings
      spans.add(
        TextSpan(
          text: text,
          style: const TextStyle(color: Color(0xFF98C379)),
        ),
      );
    } else if (m.group(4) != null) {
      // Numbers
      spans.add(
        TextSpan(
          text: text,
          style: const TextStyle(color: Color(0xFFD19A66)),
        ),
      );
    } else if (m.group(5) != null) {
      // Words
      if (keywordSet.contains(text)) {
        spans.add(
          TextSpan(
            text: text,
            style: const TextStyle(
              color: Color(0xFFC678DD),
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      } else if (RegExp(r'^[A-Z]').hasMatch(text)) {
        // Classes/Types
        spans.add(
          TextSpan(
            text: text,
            style: const TextStyle(color: Color(0xFFE5C07B)),
          ),
        );
      } else if (text == 'void' ||
          text == 'int' ||
          text == 'double' ||
          text == 'num' ||
          text == 'bool' ||
          text == 'dynamic') {
        spans.add(
          TextSpan(
            text: text,
            style: const TextStyle(color: Color(0xFFE5C07B)),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: text,
            style: const TextStyle(color: Color(0xFFABB2BF)),
          ),
        );
      }
    } else {
      // Operators, braces, spaces
      spans.add(
        TextSpan(
          text: text,
          style: const TextStyle(color: Color(0xFFABB2BF)),
        ),
      );
    }
  }

  return TextSpan(children: spans);
}

class CodeBlockWidget extends StatelessWidget {
  const CodeBlockWidget({
    required this.code,
    required this.language,
    required this.onSave,
    super.key,
  });

  final String code;
  final String language;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF2D2D2D),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.code, size: 16, color: Color(0xFFDCCBB8)),
                const SizedBox(width: 8),
                Text(
                  language.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFDCCBB8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy code',
                  icon: const Icon(
                    Icons.copy_all_outlined,
                    size: 18,
                    color: Color(0xFFDCCBB8),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied to clipboard')),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Save file',
                  icon: const Icon(
                    Icons.download_rounded,
                    size: 18,
                    color: Color(0xFFDCCBB8),
                  ),
                  onPressed: onSave,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText.rich(
              _highlightCode(code, language),
              style: GoogleFonts.jetBrainsMono(fontSize: 13, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class FileArtifactWidget extends StatelessWidget {
  const FileArtifactWidget({
    required this.content,
    required this.language,
    super.key,
  });

  final String content;
  final String language;

  String get filename => 'artifact.${getExtension(language)}';

  Future<void> _save(BuildContext context) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Artifact',
      fileName: filename,
      bytes: bytes,
    );
    if (path != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved $filename')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7D8C4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F2E8),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: Color(0xFFE7D8C4))),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.insert_drive_file_outlined,
                  size: 16,
                  color: Color(0xFF7B4E2E),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    filename,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF2D241C),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy, size: 17),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Artifact copied')),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Save',
                  icon: const Icon(Icons.download_rounded, size: 18),
                  onPressed: () => _save(context),
                ),
              ],
            ),
          ),
          Container(
            constraints: const BoxConstraints(maxHeight: 260),
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF1E1E1E),
            child: SingleChildScrollView(
              child: SelectableText.rich(
                _highlightCode(content, language),
                style: GoogleFonts.jetBrainsMono(fontSize: 12, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
