import 'package:flutter_test/flutter_test.dart';
import 'package:nexon/widgets/diff_viewer_widget.dart';

void main() {
  const sample = '--- a/test.txt\n'
      '+++ b/test.txt\n'
      '@@ -1,4 +1,4 @@\n'
      ' line one\n'
      '-old line\n'
      '+new line\n'
      ' context\n'
      '+added line\n';

  test('parses added and removed rows with line numbers', () {
    final rows = parseUnifiedDiff(sample);
    final added = rows.where((r) => r.kind == DiffLineKind.added).toList();
    final removed = rows.where((r) => r.kind == DiffLineKind.removed).toList();
    expect(added, hasLength(2));
    expect(removed, hasLength(1));
    expect(removed.single.oldLine, 2);
    expect(added.first.newLine, 2);
    expect(added.last.newLine, 4);
  });

  test('hunk header seeds line counters', () {
    final rows = parseUnifiedDiff(sample);
    final hunk = rows.firstWhere((r) => r.kind == DiffLineKind.hunk);
    expect(hunk.text, startsWith('@@ -1,4 +1,4 @@'));
    final ctx = rows.firstWhere((r) => r.kind == DiffLineKind.context);
    expect(ctx.oldLine, 1);
    expect(ctx.newLine, 1);
  });

  test('file headers detected', () {
    final rows = parseUnifiedDiff(sample);
    final files = rows.where((r) => r.kind == DiffLineKind.file).toList();
    expect(files, hasLength(2));
  });

  test('empty diff yields no rows', () {
    expect(parseUnifiedDiff(''), isEmpty);
  });

  test('crlf line endings tolerated', () {
    final rows = parseUnifiedDiff('+added\r\n context\r\n');
    expect(rows.first.kind, DiffLineKind.added);
    expect(rows[1].kind, DiffLineKind.context);
  });
}
