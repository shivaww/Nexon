import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

/// Bottom sheet showing one document page for a tapped [Source: ...] chip.
class SourcePageSheet extends StatefulWidget {
  const SourcePageSheet({
    required this.baseUrl,
    required this.sessionId,
    required this.file,
    required this.page,
    super.key,
  });

  final String baseUrl;
  final String sessionId;
  final String file;
  final int page;

  @override
  State<SourcePageSheet> createState() => _SourcePageSheetState();
}

class _SourcePageSheetState extends State<SourcePageSheet> {
  late final Future<Map<String, dynamic>> _future = _fetch();

  Future<Map<String, dynamic>> _fetch() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..findProxy = ((uri) => 'DIRECT');
    try {
      final uri = Uri.parse('${widget.baseUrl}/workspace/page').replace(
        queryParameters: {
          'session': widget.sessionId,
          'file': widget.file,
          'page': '${widget.page}',
        },
      );
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 10));
      final resp = await req.close().timeout(const Duration(seconds: 35));
      final body = await resp.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'status': 'error', 'message': 'Unexpected reply from the bridge.'};
    } catch (_) {
      return {'status': 'error', 'message': 'Could not reach the bridge.'};
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = dark ? const Color(0xFF242822) : const Color(0xFFFBF7F0);
    final text = dark ? const Color(0xFFEDE8E0) : const Color(0xFF2D241C);
    final sub = dark ? const Color(0xFF9AA096) : const Color(0xFF7B7468);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final r = snap.data!;
            final ok = r['status'] == 'success';
            final total = r['total_pages'];
            final suffix = total != null ? ' of $total' : '';
            final content = '${r['content'] ?? ''}'.trim();
            final body = ok
                ? (content.isEmpty
                    ? 'This page has no extractable text.'
                    : content)
                : '${r['message'] ?? 'Could not load this page.'}';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.file} · Page ${widget.page}$suffix',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: text,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      color: sub,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      body,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: ok ? text : sub,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
