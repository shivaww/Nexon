import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// Bottom sheet listing one chat's workspace documents, with per-file
/// removal and quota usage. Talks to the bridge's session-scoped routes.
class WorkspaceFilesSheet extends StatefulWidget {
  const WorkspaceFilesSheet({
    required this.baseUrl,
    required this.sessionId,
    super.key,
  });

  final String baseUrl;
  final String sessionId;

  @override
  State<WorkspaceFilesSheet> createState() => _WorkspaceFilesSheetState();
}

class _WorkspaceFilesSheetState extends State<WorkspaceFilesSheet> {
  Map<String, dynamic>? _data;
  String? _error;
  String? _busyPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>> _call(
    String method,
    String path,
    Map<String, String> query,
    int timeoutSeconds,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..findProxy = ((uri) => 'DIRECT');
    try {
      final uri = Uri.parse('${widget.baseUrl}$path')
          .replace(queryParameters: query);
      final req = method == 'POST'
          ? await client.postUrl(uri).timeout(const Duration(seconds: 5))
          : await client.getUrl(uri).timeout(const Duration(seconds: 5));
      if (method == 'POST') {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode('{}'));
      }
      final resp = await req.close().timeout(Duration(seconds: timeoutSeconds));
      final body = await resp.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {
        'status': 'error',
        'message': 'Unexpected reply from the bridge.',
      };
    } catch (_) {
      return {'status': 'error', 'message': 'Could not reach the bridge.'};
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _load() async {
    final r = await _call('GET', '/workspace/files', {
      'session': widget.sessionId,
    }, 15);
    if (!mounted) return;
    setState(() {
      if (r['status'] == 'success') {
        _data = r;
        _error = null;
      } else {
        _error = '${r['message'] ?? 'Could not load files.'}';
      }
    });
  }

  Future<void> _delete(String path, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove document?'),
        content: Text(
          '$name will be deleted from this chat and removed from search.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busyPath = path);
    final r = await _call('POST', '/workspace/delete', {
      'session': widget.sessionId,
      'file': path,
    }, 240);
    if (!mounted) return;
    setState(() => _busyPath = null);
    if (r['status'] != 'success') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${r['message'] ?? 'Delete failed.'}')),
      );
      return;
    }
    await _load();
  }

  String _size(num kb) => kb >= 1024
      ? '${(kb / 1024).toStringAsFixed(1)} MB'
      : '${kb.toStringAsFixed(0)} KB';

  Widget _row(Map f, Color text, Color sub) {
    final path = '${f['path']}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 18, color: sub),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${f['name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: text),
                ),
                Text(
                  _size((f['size_kb'] as num?) ?? 0),
                  style: TextStyle(fontSize: 11.5, color: sub),
                ),
              ],
            ),
          ),
          if (_busyPath == path)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              tooltip: 'Remove',
              icon: Icon(Icons.delete_outline, size: 20, color: sub),
              onPressed: _busyPath == null
                  ? () => _delete(path, '${f['name']}')
                  : null,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = dark ? const Color(0xFF242822) : const Color(0xFFFBF7F0);
    final text = dark ? const Color(0xFFEDE8E0) : const Color(0xFF2D241C);
    final sub = dark ? const Color(0xFF9AA096) : const Color(0xFF7B7468);
    final files =
        (_data?['files'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    final chatMb = ((_data?['total_used_mb'] as num?) ?? 0).toDouble();
    final globalMb = ((_data?['global_used_mb'] as num?) ?? 0).toDouble();
    final quota = ((_data?['quota_mb'] as num?) ?? 150).toDouble();
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Documents in this chat',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${chatMb.toStringAsFixed(1)} MB here, ${globalMb.toStringAsFixed(1)} of ${quota.toStringAsFixed(0)} MB used across all chats',
              style: TextStyle(fontSize: 11.5, color: sub),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: quota > 0
                  ? (globalMb / quota).clamp(0.0, 1.0).toDouble()
                  : 0,
              minHeight: 4,
            ),
            const SizedBox(height: 8),
            if (_data == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!, style: TextStyle(fontSize: 13, color: sub))
            else if (files.isEmpty)
              Text(
                'No documents uploaded in this chat.',
                style: TextStyle(fontSize: 13, color: sub),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: files.length,
                  itemBuilder: (_, i) => _row(files[i], text, sub),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
