// Extracted from main.dart lines 12513-12786
// Extracted on: 2026-08-26T18:20:45.716240

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class _QuizSheet extends StatefulWidget {
  const _QuizSheet({required this.questions, super.key});
  final List<Map<String, dynamic>> questions;

  static List<Map<String, dynamic>> parseQuestions(String json) {
    try {
      final decoded = jsonDecode(json);
      final raw = decoded is Map
          ? (decoded['questions'] is List ? decoded['questions'] as List : [decoded])
          : (decoded is List ? decoded : <dynamic>[]);
      final out = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is! Map || out.length >= 10) continue;
        final q = (item['q'] ?? item['question'] ?? '').toString();
        final opts = item['options'] is List
            ? (item['options'] as List).map((e) => e.toString()).toList()
            : <String>[];
        final correct = item['correct'] is num
            ? (item['correct'] as num).toInt()
            : int.tryParse((item['correct'] ?? '').toString()) ?? -1;
        if (q.isEmpty || opts.length < 2 || correct < 0 || correct >= opts.length) {
          continue;
        }
        out.add({'q': q, 'options': opts, 'correct': correct});
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  @override
  State<_QuizSheet> createState() => _QuizSheetState();
}

class _QuizSheetState extends State<_QuizSheet> {
  int _idx = 0;
  bool _review = false;
  final List<Map<String, dynamic>> _answers = [];
  final TextEditingController _own = TextEditingController();

  void _submit(int picked, String pickedText) {
    final q = widget.questions[_idx];
    final opts = (q['options'] as List).map((e) => e.toString()).toList();
    final correct = (q['correct'] as num).toInt();
    _answers.add({
      'q': q['q'],
      'picked': pickedText,
      'answer': opts[correct],
      'correct': picked == correct,
    });
    _own.clear();
    setState(() {
      if (_idx + 1 < widget.questions.length) {
        _idx++;
      } else {
        _review = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = dark ? const Color(0xFF242822) : const Color(0xFFFBF7F0);
    final text = dark ? const Color(0xFFEDE8E0) : const Color(0xFF2D241C);
    final sub = dark ? const Color(0xFF9AA096) : const Color(0xFF7B7468);
    const accent = Color(0xFF7B4E2E);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(16),
        child: _review ? _buildReview(text, sub) : _buildQuestion(text, sub, accent),
      ),
    );
  }

  Widget _buildQuestion(Color text, Color sub, Color accent) {
    final q = widget.questions[_idx];
    final opts = (q['options'] as List).map((e) => e.toString()).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${_idx + 1} of ${widget.questions.length}',
              style: TextStyle(fontSize: 12, color: sub),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: sub,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          q['q'] as String,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: text),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: opts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => InkWell(
              onTap: () => _submit(i, opts[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Text('${i + 1}', style: TextStyle(fontSize: 13, color: accent)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(opts[i], style: TextStyle(fontSize: 15, color: text)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _own,
                style: TextStyle(fontSize: 14, color: text),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Type your own answer...',
                  hintStyle: TextStyle(fontSize: 14, color: sub),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 18),
              color: accent,
              onPressed: () {
                final t = _own.text.trim().toLowerCase();
                if (t.isEmpty) return;
                int match = opts.indexWhere((o) => o.toLowerCase() == t);
                if (match == -1) {
                  match = opts.indexWhere((o) {
                    final ol = o.toLowerCase();
                    return ol.contains(t) || t.contains(ol);
                  });
                }
                _submit(match, _own.text.trim());
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReview(Color text, Color sub) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Results',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: text),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _answers.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final a = _answers[i];
              final ok = a['correct'] == true;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      size: 18,
                      color: ok ? const Color(0xFF3E7B3E) : const Color(0xFFB3402E),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Q${i + 1}: ${a['q']}', style: TextStyle(fontSize: 14, color: text)),
                          const SizedBox(height: 2),
                          Text(
                            ok
                                ? 'Your answer: ${a['picked']}'
                                : 'Your answer: ${a['picked']} — correct: ${a['answer']}',
                            style: TextStyle(fontSize: 12, color: sub),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7B4E2E)),
            onPressed: () => Navigator.pop(context, _answers),
            child: const Text('Continue', style: TextStyle(color: Color(0xFFFBF7F0))),
          ),
        ),
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF7B4E2E).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: const Color(0xFF7B4E2E).withOpacity(0.8)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF7B4E2E).withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}
