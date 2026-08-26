// Extracted from main.dart lines 19953-21293
// Extracted: 2026-08-26T13:43:58.959187

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:docx_creator/docx_creator.dart' hide PdfDocument;
import 'package:nexon/widgets/glass_widgets.dart';

class HtmlArtifactWidget extends StatelessWidget {
  final String htmlContent;
  const HtmlArtifactWidget({super.key, required this.htmlContent});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7D8C4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F2E8),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: Color(0xFFE7D8C4))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    getHtmlTitle(htmlContent),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            FullScreenHtmlViewer(htmlContent: htmlContent),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF7B4E2E),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text(
                    'View File',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 200,
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Text(
                htmlContent,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFFD4D4D4),
                  fontSize: 12,
                ),
                maxLines: 50,
                overflow: TextOverflow.fade,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FullScreenHtmlViewer extends StatefulWidget {
  final String htmlContent;
  const FullScreenHtmlViewer({super.key, required this.htmlContent});

  @override
  State<FullScreenHtmlViewer> createState() => _FullScreenHtmlViewerState();
}

class _FullScreenHtmlViewerState extends State<FullScreenHtmlViewer> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _showPreview = false;

  @override
  void initState() {
    super.initState();
    final html = widget.htmlContent;
    final wrappedHtml = html.contains('<html')
        ? html
        : '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; margin: 0; padding: 16px; background-color: #ffffff; }
  </style>
</head>
<body>
  \$html
</body>
</html>
''';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (request.url.startsWith('http')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadHtmlString(wrappedHtml);
  }

  Future<void> _downloadFile() async {
    try {
      final filename = 'page_${DateTime.now().millisecondsSinceEpoch}.html';
      final bytes = Uint8List.fromList(utf8.encode(widget.htmlContent));
      final String? path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save HTML Page',
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to ${path.split('/').last}'),
            backgroundColor: const Color(0xFF36764D),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving file: $e'),
            backgroundColor: const Color(0xFF9B4D39),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showPreview ? 'Preview' : 'HTML Code'),
        backgroundColor: const Color(0xFFF7F2E8),
        foregroundColor: const Color(0xFF2D241C),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF2D241C)),
            onSelected: (value) {
              if (value == 'copy') {
                Clipboard.setData(ClipboardData(text: widget.htmlContent));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              } else if (value == 'preview') {
                setState(() => _showPreview = !_showPreview);
              } else if (value == 'download') {
                _downloadFile();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'copy', child: Text('Copy')),
              PopupMenuItem(
                value: 'preview',
                child: Text(_showPreview ? 'Show Code' : 'Preview'),
              ),
              const PopupMenuItem(value: 'download', child: Text('Download')),
            ],
          ),
        ],
      ),
      body: _showPreview
          ? Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator()),
              ],
            )
          : Container(
              color: const Color(0xFF1E1E1E),
              width: double.infinity,
              height: double.infinity,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SelectableText(
                    widget.htmlContent,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFFD4D4D4),
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class SvgDiagramWidget extends StatefulWidget {
  final String svgString;
  final Function(String errorDetails)? onError;

  const SvgDiagramWidget({super.key, required this.svgString, this.onError});

  @override
  State<SvgDiagramWidget> createState() => _SvgDiagramWidgetState();
}

class _SvgDiagramWidgetState extends State<SvgDiagramWidget> {
  late String _cachedSvg;
  late bool _isComplete;
  bool _hasError = false;
  String _errorMessage = '';
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _processSvg();
  }

  void _processSvg() {
    _cachedSvg = _cleanSvg(widget.svgString);
    _isComplete = _cachedSvg.trim().endsWith('</svg>');

    if (!_isComplete) {
      _startTimeoutTimer();
    } else {
      _timeoutTimer?.cancel();
      _validateSvg();
    }
  }

  void _startTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && !_isComplete) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Incomplete SVG visual stream (missing </svg> tag)';
        });
        widget.onError?.call(_errorMessage);
      }
    });
  }

  void _validateSvg() {
    if (!_cachedSvg.contains('<svg')) {
      _hasError = true;
      _errorMessage = 'Invalid SVG content (missing <svg> tag)';
      widget.onError?.call(_errorMessage);
      return;
    }
    _hasError = false;
  }

  @override
  void didUpdateWidget(SvgDiagramWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.svgString != widget.svgString) {
      _processSvg();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  String _cleanSvg(String raw) {
    String s = raw.trim();
    final svgIdx = s.indexOf('<svg');
    if (svgIdx < 0) return s;
    if (svgIdx > 0) s = s.substring(svgIdx);

    s = s.replaceFirstMapped(
      RegExp(
        r'''(<svg[^>]*?)\s+width=["']?[\d.%]+["']?''',
        caseSensitive: false,
      ),
      (m) => m.group(1)!,
    );
    s = s.replaceFirstMapped(
      RegExp(
        r'''(<svg[^>]*?)\s+height=["']?[\d.%]+["']?''',
        caseSensitive: false,
      ),
      (m) => m.group(1)!,
    );
    s = s.replaceAllMapped(
      RegExp(r'''<use\s+[^>]*href=["']https?://[^"']*["'][^>]*/>''', caseSensitive: false),
      (_) => '',
    );
    s = s.replaceAllMapped(
      RegExp(r'''<image\s+[^>]*href=["']https?://[^"']*["'][^>]*/?>''', caseSensitive: false),
      (_) => '',
    );
    s = s.replaceAllMapped(
      RegExp(r'''xlink:href=["']https?://[^"']*["']''', caseSensitive: false),
      (_) => 'xlink:href=""',
    );
    s = s.replaceAllMapped(
      RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
      (_) => '',
    );
    s = s.replaceAllMapped(
      RegExp(r'<foreignObject[^>]*>[\s\S]*?</foreignObject>', caseSensitive: false),
      (_) => '',
    );
    s = s.replaceAllMapped(
      RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
      (_) => '',
    );
    s = s.replaceAllMapped(
      RegExp(r'''\son\w+\s*=\s*["'][^"']*["']''', caseSensitive: false),
      (_) => '',
    );
    s = s.replaceAllMapped(
      RegExp(r'javascript:', caseSensitive: false),
      (_) => '',
    );
    return s;
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFDC2626),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Failed to render visual: ${_errorMessage.length > 55 ? "${_errorMessage.substring(0, 55)}…" : _errorMessage}',
                style: const TextStyle(
                  color: Color(0xFF991B1B),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!_isComplete) {
      return Container(
        width: double.infinity,
        height: 80,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1B2A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF1E3A5F).withValues(alpha: 0.5),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Generating visual…',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
    }

    // SVG is complete — render it directly on chat background, no card
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Parse viewBox to derive aspect ratio
          double aspectRatio = 16 / 9;
          final vbMatch = RegExp(
            r'''viewBox=["']\s*([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)\s*["']''',
            caseSensitive: false,
          ).firstMatch(_cachedSvg);
          if (vbMatch != null) {
            final w = double.tryParse(vbMatch.group(3) ?? '') ?? 0;
            final h = double.tryParse(vbMatch.group(4) ?? '') ?? 0;
            if (w > 0 && h > 0) {
              aspectRatio = (w / h).clamp(0.3, 5.0);
            }
          }

          final availWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.of(context).size.width - 32;
          final renderHeight = (availWidth / aspectRatio).clamp(180.0, 520.0);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        FullScreenSvgViewer(svgString: _cachedSvg),
                  ),
                );
              },
              child: SizedBox(
                width: double.infinity,
                height: renderHeight,
                child: SvgPicture.string(
                  _cachedSvg,
                  fit: BoxFit.contain,
                  width: availWidth,
                  height: renderHeight,
                  placeholderBuilder: (_) => const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Color(0xFF6366F1),
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                  // IMPROVEMENT: malformed AI-generated SVG previously left the
                  // placeholder spinner on screen forever; show an error card.
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xFFDC2626),
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Failed to render visual: invalid SVG code',
                            style: TextStyle(
                              color: Color(0xFF991B1B),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class FullScreenSvgViewer extends StatelessWidget {
  const FullScreenSvgViewer({required this.svgString, super.key});
  final String svgString;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                panEnabled: true,
                scaleEnabled: true,
                minScale: 0.5,
                maxScale: 10.0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SvgPicture.string(
                    svgString,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Failed to render SVG: the generated code is invalid.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 14,
              right: 14,
              child: WarmGlassContainer(
                borderRadius: BorderRadius.circular(16),
                backgroundColor: const Color(
                  0xFF0D1B2A,
                ).withValues(alpha: 0.72),
                border: Border.all(
                  color: const Color(0xFF1E3A5F).withValues(alpha: 0.6),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                sigma: 10.0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_all, color: Colors.white),
                      tooltip: 'Copy SVG code',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: svgString));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('SVG code copied to clipboard'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Document Artifacts & File Permission Helpers ──────────────────────────

String getHtmlTitle(String content) {
  final match = RegExp(
    r'<title>(.*?)</title>',
    caseSensitive: false,
  ).firstMatch(content);
  if (match != null) {
    final title = match.group(1)?.trim() ?? '';
    if (title.isNotEmpty) return title;
  }
  return 'HTML Document';
}

String getDocxTitle(String content) {
  final titleMatch = RegExp(
    r'^title:\s*(.*)$',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(content);
  if (titleMatch != null) {
    final title = titleMatch.group(1)?.trim() ?? '';
    if (title.isNotEmpty) return title;
  }
  final h1Match = RegExp(r'^#\s*(.*)$', multiLine: true).firstMatch(content);
  if (h1Match != null) {
    final title = h1Match.group(1)?.trim() ?? '';
    if (title.isNotEmpty) return title;
  }
  return 'Word Document';
}

String getMdTitle(String content) {
  final titleMatch = RegExp(
    r'^title:\s*(.*)$',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(content);
  if (titleMatch != null) {
    final title = titleMatch.group(1)?.trim() ?? '';
    if (title.isNotEmpty) return title;
  }
  final h1Match = RegExp(r'^#\s*(.*)$', multiLine: true).firstMatch(content);
  if (h1Match != null) {
    final title = h1Match.group(1)?.trim() ?? '';
    if (title.isNotEmpty) return title;
  }
  return 'Markdown Document';
}

// ── Docx Artifact Widget ──

class DocxArtifactWidget extends StatelessWidget {
  final String docxContent;
  final String workspacePath;
  const DocxArtifactWidget({
    super.key,
    required this.docxContent,
    required this.workspacePath,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7D8C4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F2E8),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: Color(0xFFE7D8C4))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    getDocxTitle(docxContent),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FullScreenDocxViewer(
                          docxContent: docxContent,
                          workspacePath: workspacePath,
                        ),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF7B4E2E),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text(
                    'View File',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 150,
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Text(
                docxContent,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFFD4D4D4),
                  fontSize: 12,
                ),
                maxLines: 50,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Full Screen Docx Viewer ──

class FullScreenDocxViewer extends StatefulWidget {
  final String docxContent;
  final String workspacePath;
  const FullScreenDocxViewer({
    super.key,
    required this.docxContent,
    required this.workspacePath,
  });

  @override
  State<FullScreenDocxViewer> createState() => _FullScreenDocxViewerState();
}

class _FullScreenDocxViewerState extends State<FullScreenDocxViewer> {
  bool _showPreview = true;
  bool _exporting = false;

  Future<void> _exportDocx() async {
    setState(() => _exporting = true);

    try {
      // Use docx_creator to generate the DOCX natively in Dart
      final elements = await MarkdownParser.parse(widget.docxContent);
      final doc = DocxBuiltDocument(elements: elements);
      final docxBytes = await DocxExporter().exportToBytes(doc);

      // Determine filename from content
      String filename = 'document.docx';
      final match = RegExp(
        r'^title:\s*(.*)$',
        multiLine: true,
        caseSensitive: false,
      ).firstMatch(widget.docxContent);
      if (match != null) {
        final title =
            match.group(1)?.replaceAll(RegExp(r'[^a-zA-Z0-9\s-]'), '').trim() ??
            '';
        if (title.isNotEmpty) {
          filename = '${title.toLowerCase().replaceAll(' ', '_')}.docx';
        }
      }

      final String? savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Word Document',
        fileName: filename,
        bytes: Uint8List.fromList(docxBytes),
      );

      if (savePath == null) {
        return;
      }

      if (!Platform.isAndroid && !Platform.isIOS) {
        final file = File(savePath);
        await file.writeAsBytes(docxBytes);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to ${savePath.split('/').last}'),
            backgroundColor: const Color(0xFF36764D),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export document: $e'),
            backgroundColor: const Color(0xFF9B4D39),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showPreview ? 'Word Preview' : 'Word Content'),
        backgroundColor: const Color(0xFFF7F2E8),
        foregroundColor: const Color(0xFF2D241C),
        actions: [
          if (_exporting)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF7B4E2E),
                  ),
                ),
              ),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Color(0xFF2D241C)),
              onSelected: (value) {
                if (value == 'copy') {
                  Clipboard.setData(ClipboardData(text: widget.docxContent));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                } else if (value == 'preview') {
                  setState(() => _showPreview = !_showPreview);
                } else if (value == 'download') {
                  _exportDocx();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'copy', child: Text('Copy')),
                PopupMenuItem(
                  value: 'preview',
                  child: Text(_showPreview ? 'Show Code' : 'Preview'),
                ),
                const PopupMenuItem(
                  value: 'download',
                  child: Text('Download (.docx)'),
                ),
              ],
            ),
        ],
      ),
      body: _showPreview
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 800),
                  padding: const EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFDF2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5DDD3)),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: MarkdownBody(
                    data: widget.docxContent,
                    selectable: true,
                    extensionSet: md.ExtensionSet.gitHubFlavored,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                        .copyWith(
                          tableColumnWidth: const IntrinsicColumnWidth(),
                          tableHeadAlign: TextAlign.left,
                          h1: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF7B4E2E),
                            fontFamily: 'serif',
                          ),
                          h2: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF7B4E2E),
                            fontFamily: 'serif',
                          ),
                          h3: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF6C5946),
                          ),
                          p: const TextStyle(
                            fontSize: 13.5,
                            height: 1.4,
                            color: Color(0xFF2D241C),
                          ),
                          blockquoteDecoration: BoxDecoration(
                            color: const Color(0xFFFAF5EE),
                            border: const Border(
                              left: BorderSide(
                                color: Color(0xFF7B4E2E),
                                width: 4.0,
                              ),
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          tableBorder: TableBorder.all(
                            color: const Color(0xFFE5DDD3),
                          ),
                          tableCellsPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          tableHead: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF7B4E2E),
                          ),
                        ),
                  ),
                ),
              ),
            )
          : Container(
              color: const Color(0xFF1E1E1E),
              width: double.infinity,
              height: double.infinity,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SelectableText(
                    widget.docxContent,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFFD4D4D4),
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

// ── Md Artifact Widget ──

class MdArtifactWidget extends StatelessWidget {
  final String mdContent;
  final String workspacePath;
  const MdArtifactWidget({
    super.key,
    required this.mdContent,
    required this.workspacePath,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7D8C4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F2E8),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: Color(0xFFE7D8C4))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    getMdTitle(mdContent),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FullScreenMdViewer(
                          mdContent: mdContent,
                          workspacePath: workspacePath,
                        ),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF7B4E2E),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text(
                    'View File',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 150,
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Text(
                mdContent,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFFD4D4D4),
                  fontSize: 12,
                ),
                maxLines: 50,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Full Screen Md Viewer ──

class FullScreenMdViewer extends StatefulWidget {
  final String mdContent;
  final String workspacePath;
  const FullScreenMdViewer({
    super.key,
    required this.mdContent,
    required this.workspacePath,
  });

  @override
  State<FullScreenMdViewer> createState() => _FullScreenMdViewerState();
}

class _FullScreenMdViewerState extends State<FullScreenMdViewer> {
  bool _showPreview = true;
  bool _saving = false;

  Future<void> _saveMdFile() async {
    setState(() => _saving = true);

    try {
      String filename = 'document.md';
      final match = RegExp(
        r'^title:\s*(.*)$',
        multiLine: true,
        caseSensitive: false,
      ).firstMatch(widget.mdContent);
      if (match != null) {
        final title =
            match.group(1)?.replaceAll(RegExp(r'[^a-zA-Z0-9\s-]'), '').trim() ??
            '';
        if (title.isNotEmpty) {
          filename = '${title.toLowerCase().replaceAll(' ', '_')}.md';
        }
      }

      final bytes = Uint8List.fromList(utf8.encode(widget.mdContent));
      final String? path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Markdown File',
        fileName: filename,
        bytes: bytes,
      );

      if (path == null) {
        return;
      }

      if (!Platform.isAndroid && !Platform.isIOS) {
        final file = File(path);
        await file.writeAsBytes(bytes);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to ${path.split('/').last}'),
            backgroundColor: const Color(0xFF36764D),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving file: $e'),
            backgroundColor: const Color(0xFF9B4D39),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showPreview ? 'Markdown Preview' : 'Markdown Code'),
        backgroundColor: const Color(0xFFF7F2E8),
        foregroundColor: const Color(0xFF2D241C),
        actions: [
          if (_saving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF7B4E2E),
                  ),
                ),
              ),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Color(0xFF2D241C)),
              onSelected: (value) {
                if (value == 'copy') {
                  Clipboard.setData(ClipboardData(text: widget.mdContent));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                } else if (value == 'preview') {
                  setState(() => _showPreview = !_showPreview);
                } else if (value == 'download') {
                  _saveMdFile();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'copy', child: Text('Copy')),
                PopupMenuItem(
                  value: 'preview',
                  child: Text(_showPreview ? 'Show Code' : 'Preview'),
                ),
                const PopupMenuItem(
                  value: 'download',
                  child: Text('Download (.md)'),
                ),
              ],
            ),
        ],
      ),
      body: _showPreview
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 800),
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE7D8C4)),
                  ),
                  child: MarkdownBody(
                    data: widget.mdContent,
                    selectable: true,
                    extensionSet: md.ExtensionSet.gitHubFlavored,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                        .copyWith(
                          tableColumnWidth: const IntrinsicColumnWidth(),
                          tableHeadAlign: TextAlign.left,
                          tableBorder: TableBorder.all(
                            color: const Color(0xFFE7D8C4),
                            width: 1,
                          ),
                        ),
                  ),
                ),
              ),
            )
          : Container(
              color: const Color(0xFF1E1E1E),
              width: double.infinity,
              height: double.infinity,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SelectableText(
                    widget.mdContent,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFFD4D4D4),
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

String _resolvePath(String p, String workspace) {
  if (p.startsWith('http://') || p.startsWith('https://')) return p;
  String expandHome(String path) {
    if (path == '~') {
      return Platform.environment['HOME'] ?? '/data/data/com.termux/files/home';
    }
    if (path.startsWith('~/')) {
      final home =
          Platform.environment['HOME'] ?? '/data/data/com.termux/files/home';
      return '$home/${path.substring(2)}';
    }
    return path;
  }

  String normalize(String path) {
    final normalized = Uri.file(path).normalizePath().toFilePath();
    if (normalized.length > 1 && normalized.endsWith('/')) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  final workspaceExpanded = expandHome(workspace);
  final workspaceCanonical = normalize(
    workspaceExpanded.startsWith('/')
        ? workspaceExpanded
        : Directory.current.uri.resolve(workspaceExpanded).toFilePath(),
  );

  final candidateBase = expandHome(p);
  final candidateResolved = candidateBase.startsWith('/')
      ? candidateBase
      : '$workspaceCanonical/$candidateBase';
  final candidateCanonical = normalize(candidateResolved);
  final insideWorkspace = candidateCanonical == workspaceCanonical ||
      candidateCanonical.startsWith('$workspaceCanonical/');
  if (!insideWorkspace) {
    throw StateError('outside workspace jail: $candidateCanonical');
  }
  return candidateCanonical;
}

dynamic resolveToolPathValue(dynamic value, String workspace, [String? key]) {
  const pathKeys = {
    'path',
    'file',
    'directory',
    'dir',
    'dir_path',
    'src',
    'dest',
    'path_a',
    'path_b',
    'target',
    'output_dir',
  };
  if (value is Map<String, dynamic>) {
    return value.map(
      (k, v) => MapEntry(k, resolveToolPathValue(v, workspace, k)),
    );
  }
  if (value is List) {
    return value
        .map((item) => resolveToolPathValue(item, workspace, key))
        .toList();
  }
  if (value is String && key != null && pathKeys.contains(key)) {
    return _resolvePath(value, workspace);
  }
  return value;
}
