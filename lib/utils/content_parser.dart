// Extracted from main.dart lines 10012-10324
// Extracted on: 2026-08-26T18:20:45.726103

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

String getExtension(String lang) {
  switch (lang.toLowerCase()) {
    case 'python':
    case 'py':
      return 'py';
    case 'dart':
      return 'dart';
    case 'javascript':
    case 'js':
      return 'js';
    case 'typescript':
    case 'ts':
      return 'ts';
    case 'html':
      return 'html';
    case 'css':
      return 'css';
    case 'json':
      return 'json';
    case 'bash':
    case 'sh':
    case 'shell':
      return 'sh';
    case 'rust':
    case 'rs':
      return 'rs';
    case 'go':
      return 'go';
    case 'cpp':
    case 'c++':
      return 'cpp';
    case 'c':
      return 'c';
    case 'java':
      return 'java';
    case 'kotlin':
    case 'kt':
      return 'kt';
    default:
      return 'txt';
  }
}

Future<void> saveCodeBlock(
  BuildContext context,
  String code,
  String language,
) async {
  try {
    final ext = getExtension(language);
    final filename = 'code_${DateTime.now().millisecondsSinceEpoch}.$ext';

    if (Platform.isAndroid) {
      await Permission.storage.request();
    }

    final bytes = Uint8List.fromList(utf8.encode(code));
    final String? path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Code Block',
      fileName: filename,
      bytes: bytes,
    );

    if (path == null) {
      return; // User cancelled
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      final file = File(path);
      await file.writeAsBytes(bytes);
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File saved: ${path.split('/').last}'),
          backgroundColor: const Color(0xFF36764D),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save file: $e'),
          backgroundColor: const Color(0xFF9B4D39),
        ),
      );
    }
  }
}

class ContentBlock {
  final bool isCode;
  final String content;
  final String language;

  ContentBlock({
    required this.isCode,
    required this.content,
    this.language = '',
  });
}

List<ContentBlock> parseContentBlocks(String text) {
  final blocks = <ContentBlock>[];
  final parts = text.split('```');

  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    if (i % 2 == 0) {
      if (part.isNotEmpty) {
        blocks.add(ContentBlock(isCode: false, content: part));
      }
    } else {
      final lines = part.split('\n');
      final firstLine = lines.first.trim();

      bool isValidLanguageIdentifier(String lang) {
        if (lang.isEmpty) return true;
        final invalidChars = RegExp(r"[\s\(\)\{\}\[\]\=\*\/\\;,'\.]");
        return !invalidChars.hasMatch(lang) && lang.length <= 20;
      }

      if (isValidLanguageIdentifier(firstLine)) {
        final codeContent = lines.skip(1).join('\n');
        blocks.add(
          ContentBlock(isCode: true, content: codeContent, language: firstLine),
        );
      } else {
        blocks.add(ContentBlock(isCode: true, content: part, language: ''));
      }
    }
  }
  return blocks;
}

String convertLatexToUnicode(String text) {
  var formatted = text;

  final replacements = {
    r'\alpha': 'α',
    r'\beta': 'β',
    r'\gamma': 'γ',
    r'\delta': 'δ',
    r'\epsilon': 'ε',
    r'\zeta': 'ζ',
    r'\eta': 'η',
    r'\theta': 'θ',
    r'\iota': 'ι',
    r'\kappa': 'κ',
    r'\lambda': 'λ',
    r'\mu': 'μ',
    r'\nu': 'ν',
    r'\xi': 'ξ',
    r'\pi': 'π',
    r'\rho': 'ρ',
    r'\sigma': 'σ',
    r'\tau': 'τ',
    r'\upsilon': 'υ',
    r'\phi': 'φ',
    r'\chi': 'χ',
    r'\psi': 'ψ',
    r'\omega': 'ω',
    r'\Gamma': 'Γ',
    r'\Delta': 'Δ',
    r'\Theta': 'Θ',
    r'\Lambda': 'Λ',
    r'\Xi': 'Ξ',
    r'\Pi': 'Π',
    r'\Sigma': 'Σ',
    r'\Phi': 'Φ',
    r'\Psi': 'Ψ',
    r'\Omega': 'Ω',
    r'\pm': '±',
    r'\times': '×',
    r'\div': '÷',
    r'\cdot': '·',
    r'\le': '≤',
    r'\ge': '≥',
    r'\ne': '≠',
    r'\approx': '≈',
    r'\in': '∈',
    r'\notin': '∉',
    r'\ni': '∋',
    r'\propto': '∝',
    r'\infty': '∞',
    r'\partial': '∂',
    r'\nabla': '∇',
    r'\sum': '∑',
    r'\prod': '∏',
    r'\coprod': '∐',
    r'\int': '∫',
    r'\iint': '∬',
    r'\iiint': '∌',
    r'\oint': '∮',
    r'\therefore': '∴',
    r'\because': '∌',
    r'\forall': '∀',
    r'\exists': '∃',
    r'\empty': '∅',
    r'\emptyset': '∅',
    r'\cap': '∩',
    r'\cup': '∪',
    r'\subset': '⊂',
    r'\supset': '⊃',
    r'\subseteq': '⊆',
    r'\supseteq': '⊇',
    r'\leftrightarrow': '↔',
    r'\Leftarrow': '⇐',
    r'\Rightarrow': '⇒',
    r'\Leftrightarrow': '⇔',
    r'\to': '→',
    r'\rightarrow': '→',
    r'\gets': '←',
    r'\leftarrow': '←',
    r'\uparrow': '↑',
    r'\downarrow': '↓',
    r'\neq': '≠',
    r'\leq': '≤',
    r'\geq': '≥',
  };

  final sqrtRegex = RegExp(r'\\sqrt\s*\{\s*(.*?)\s*\}', dotAll: true);
  formatted = formatted.replaceAllMapped(sqrtRegex, (match) {
    final inside = match.group(1) ?? '';
    return '√($inside)';
  });

  final fracRegex = RegExp(
    r'\\frac\s*\{\s*(.*?)\s*\}\s*\{\s*(.*?)\s*\}',
    dotAll: true,
  );
  formatted = formatted.replaceAllMapped(fracRegex, (match) {
    final num = match.group(1) ?? '';
    final den = match.group(2) ?? '';
    return '($num)/($den)';
  });

  formatted = formatted.replaceAll(r'\left(', '(');
  formatted = formatted.replaceAll(r'\right)', ')');
  formatted = formatted.replaceAll(r'\left[', '[');
  formatted = formatted.replaceAll(r'\right]', ']');
  formatted = formatted.replaceAll(r'\left\{', '{');
  formatted = formatted.replaceAll(r'\right\}', '}');
  formatted = formatted.replaceAll(r'\langle', '⟨');
  formatted = formatted.replaceAll(r'\rangle', '⟩');

  replacements.forEach((key, val) {
    formatted = formatted.replaceAll(key, val);
  });

  final superscriptMap = {
    '0': '⁰',
    '1': '¹',
    '2': '²',
    '3': '³',
    '4': '⁴',
    '5': '⁵',
    '6': '⁶',
    '7': '⁷',
    '8': '⁸',
    '9': '⁹',
    '+': '⁺',
    '-': '⁻',
    '=': '⁼',
    '(': '⁽',
    ')': '⁾',
    'n': 'ⁿ',
    'i': 'ⁱ',
    'x': 'ˣ',
    'y': 'ʸ',
  };
  final superRegex = RegExp(r'\^([0-9a-nixy\+\-\=\(\)])');
  formatted = formatted.replaceAllMapped(superRegex, (match) {
    final char = match.group(1) ?? '';
    return superscriptMap[char] ?? '^$char';
  });

  final subscriptMap = {
    '0': '₀',
    '1': '₁',
    '2': '₂',
    '3': '₃',
    '4': '₄',
    '5': '₅',
    '6': '₆',
    '7': '₇',
    '8': '₈',
    '9': '₉',
    '+': '₊',
    '-': '₋',
    '=': '₌',
    '(': '₍',
    ')': '₎',
    'x': 'ₓ',
    'y': 'y',
    'i': 'ᵢ',
    'j': 'ⱼ',
  };
  final subRegex = RegExp(r'_([0-9\+\-\=\(\)xyij])');
  formatted = formatted.replaceAllMapped(subRegex, (match) {
    final char = match.group(1) ?? '';
    return subscriptMap[char] ?? '_$char';
  });

  formatted = formatted.replaceAllMapped(
    RegExp(r'\\text\s*\{\s*(.*?)\s*\}'),
    (m) => m.group(1) ?? '',
  );

  return formatted;
}
