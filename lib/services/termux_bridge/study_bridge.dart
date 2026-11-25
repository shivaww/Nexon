import 'dart:convert';
import 'dart:io';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Pings the Termux bridge with the same request the Study Mode pill uses.
/// Returns true only when the bridge answers {"result":{"ok":true}}.
Future<bool> probeBridge(String customMcpUrl) async {
  final custom = customMcpUrl.trim();
  final endpoint = custom.isNotEmpty ? custom : 'http://127.0.0.1:8390/mcp';
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    ..findProxy = ((uri) => 'DIRECT');
  try {
    final request = await client
        .postUrl(Uri.parse(endpoint))
        .timeout(const Duration(seconds: 3));
    request.headers.contentType = ContentType.json;
    final bytes = utf8.encode(jsonEncode({'method': 'ping', 'params': {}}));
    request.headers.contentLength = bytes.length;
    request.add(bytes);
    final response =
        await request.close().timeout(const Duration(seconds: 3));
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 3));
    final decoded = jsonDecode(body);
    return response.statusCode >= 200 &&
        response.statusCode < 300 &&
        decoded is Map &&
        decoded['result'] is Map &&
        (decoded['result'] as Map)['ok'] == true;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

/// Extracts PDF text with "[Page N]" markers so the model can cite pages
/// when the file is sent inline (no Termux workspace).
String extractPdfWithPageMarkers(PdfDocument document) {
  final extractor = PdfTextExtractor(document);
  final buffer = StringBuffer();
  final count = document.pages.count;
  for (var i = 0; i < count; i++) {
    final pageText =
        extractor.extractText(startPageIndex: i, endPageIndex: i).trim();
    if (pageText.isEmpty) continue;
    buffer
      ..writeln('[Page ${i + 1}]')
      ..writeln(pageText)
      ..writeln();
  }
  return buffer.toString();
}
