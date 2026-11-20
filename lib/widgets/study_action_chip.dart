import 'package:flutter/material.dart';

/// One quick study prompt shown as a tappable chip in Study Mode.
class StudyAction {
  const StudyAction(this.label, this.icon, this.prompt);
  final String label;
  final IconData icon;
  final String prompt;
}

const List<StudyAction> kStudyActions = [
  StudyAction(
    'Summarize',
    Icons.notes,
    'Summarize my uploaded documents briefly. Cite sources.',
  ),
  StudyAction(
    'Key points',
    Icons.format_list_bulleted,
    'List the key points from my uploaded documents. Cite sources.',
  ),
  StudyAction(
    'Quiz me',
    Icons.quiz_outlined,
    'Quiz me now on what my uploaded documents cover. Use the quiz tool.',
  ),
  StudyAction(
    'Explain simply',
    Icons.lightbulb_outline,
    'Explain the main idea of my uploaded documents in simple terms. Cite sources.',
  ),
];

class StudyActionChip extends StatelessWidget {
  const StudyActionChip({required this.action, required this.onTap, super.key});

  final StudyAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF7B4E2E);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(action.icon, size: 11, color: accent),
            const SizedBox(width: 4),
            Text(
              action.label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
