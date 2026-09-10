import 'package:ai_review/ai_review.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('ReviewFindings.parse', () {
    test('reads findings and orders them by severity', () {
      const body = '''
{"findings": [
  {"severity": "nit", "file": "a.dart", "title": "n", "detail": "d"},
  {"severity": "blocker", "file": "b.dart", "line": 7, "title": "b", "detail": "d"},
  {"severity": "risk", "file": "c.dart", "title": "r", "detail": "d"}
]}''';

      final findings = ReviewFindings.parse(body).valueOrNull!;

      expect(findings.map((f) => f.severity), [
        Severity.blocker,
        Severity.risk,
        Severity.nit,
      ]);
      expect(findings.first.line, 7);
      expect(findings.last.line, isNull);
    });

    test('an empty array is a clean review, not an error', () {
      expect(ReviewFindings.parse('{"findings": []}').valueOrNull, isEmpty);
    });

    test('a finding missing what a reader needs fails the whole review', () {
      // Dropping it would leave a comment that says "nothing found"
      // about a change the model did have something to say about.
      for (final finding in [
        '{"severity": "blocker", "file": "", "title": "t", "detail": "d"}',
        '{"severity": "wat", "file": "a.dart", "title": "t", "detail": "d"}',
        '{"severity": "risk", "file": "a.dart", "title": "", "detail": "d"}',
        '{"file": "a.dart", "title": "t", "detail": "d"}',
        '"a string where an object should be"',
      ]) {
        expect(
          ReviewFindings.parse('{"findings": [$finding]}'),
          isA<Err<Object, String>>(),
          reason: finding,
        );
      }
    });

    test('a line number that is not one is dropped, the finding stays', () {
      const body = '''
{"findings": [
  {"severity": "risk", "file": "a.dart", "line": -3, "title": "t", "detail": "d"}
]}''';

      expect(ReviewFindings.parse(body).valueOrNull!.single.line, isNull);
    });

    test('a broken document is an error: silence would read as approval', () {
      for (final body in ['', 'not json', '[]', '{"findings": {}}']) {
        expect(
          ReviewFindings.parse(body),
          isA<Err<Object, String>>(),
          reason: body,
        );
      }
    });
  });
}
