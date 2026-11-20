/// Pure helpers for the per-chat list of quiz questions the user missed.
/// No Flutter imports, so they can be checked with plain `dart`.

const int kMaxSavedMistakes = 50;

String _mistakeKey(Object? q) => '$q'.trim().toLowerCase();

/// Folds the questions missed in one finished quiz into [existing].
///
/// A quiz answer carries 'wrong_pick' only when the user picked a wrong
/// option at least once, even if a retry then fixed it. Free-text answers
/// that the tutor grades have no wrong_pick and are never saved. A re-missed
/// question replaces its older entry, and newest entries come first.
List<Map<String, dynamic>> mergeQuizMistakes(
  List<Map<String, dynamic>> existing,
  List<Map<String, dynamic>> answers,
  DateTime now,
) {
  final fresh = <Map<String, dynamic>>[];
  for (final a in answers) {
    final wrong = a['wrong_pick'];
    if (wrong == null) continue;
    fresh.add({
      'q': '${a['q']}',
      'wrong': '$wrong',
      'answer': '${a['answer']}',
      'fixed': a['correct'] == true,
      'at': now.toIso8601String(),
    });
  }
  if (fresh.isEmpty) return existing;
  final freshKeys = {for (final m in fresh) _mistakeKey(m['q'])};
  final kept = existing.where((m) => !freshKeys.contains(_mistakeKey(m['q'])));
  return [...fresh, ...kept].take(kMaxSavedMistakes).toList();
}
