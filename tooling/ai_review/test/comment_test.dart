import 'package:ai_insights/ai_insights.dart';
import 'package:ai_review/ai_review.dart';
import 'package:test/test.dart';

const _diff = ReviewDiff(
  text: 'diff',
  files: ['a.dart', 'b.dart'],
  skipped: [],
  truncated: [],
);

String render(List<Finding> findings, {ReviewDiff diff = _diff}) =>
    renderComment(
      findings,
      diff: diff,
      model: 'claude-haiku-4-5',
      usage: const Usage(inputTokens: 1000, outputTokens: 200),
      costUsd: 0.002,
    );

void main() {
  group('renderComment', () {
    test('carries the marker a rerun finds its own comment by', () {
      expect(render(const []), contains(commentMarker));
    });

    test('says what was read when it found nothing', () {
      expect(render(const []), contains('Nothing found in 2 files'));
    });

    test('groups findings under their severity, blockers first', () {
      final body = render(const [
        Finding(
          severity: Severity.blocker,
          file: 'a.dart',
          line: 12,
          title: 'the stream is never cancelled',
          detail: 'Leaving the screen leaves the socket open.',
        ),
        Finding(
          severity: Severity.nit,
          file: 'b.dart',
          line: null,
          title: 'the name says list, the thing is a set',
          detail: 'Callers iterate expecting order.',
        ),
      ]);

      expect(body.indexOf('Blockers'), lessThan(body.indexOf('Nits')));
      expect(body, contains('`a.dart:12`'));
      // No line means the finding is about the file, not a place in it.
      expect(body, contains('`b.dart`'));
      expect(body, isNot(contains('b.dart:')));
    });

    test('a partial review says so instead of reading as a clean one', () {
      final body = render(
        const [],
        diff: const ReviewDiff(
          text: 'diff',
          files: ['a.dart'],
          skipped: [],
          truncated: ['huge.dart'],
        ),
      );

      expect(body, contains('Not reviewed'));
      expect(body, contains('`huge.dart`'));
    });

    test('the footer accounts for the call', () {
      final body = render(const []);

      expect(body, contains('claude-haiku-4-5'));
      expect(body, contains('1000 in, 200 out'));
      expect(body, contains(r'$0.0020'));
    });
  });
}
