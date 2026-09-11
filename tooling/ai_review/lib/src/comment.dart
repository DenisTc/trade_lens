import 'package:ai_insights/ai_insights.dart';
import 'package:ai_review/src/diff.dart';
import 'package:ai_review/src/findings.dart';

/// The marker that lets a rerun find and replace its own comment instead
/// of leaving a new one on every push.
const commentMarker = '<!-- tradelens-ai-review -->';

/// Renders the comment. It says what was read as plainly as what was
/// found: a review of half a diff is not a clean bill of health.
String renderComment(
  List<Finding> findings, {
  required ReviewDiff diff,
  required String model,
  required Usage usage,
  required double costUsd,
}) {
  final b = StringBuffer()
    ..writeln(commentMarker)
    ..writeln('### AI review');

  if (findings.isEmpty) {
    b.writeln('\nNothing found in ${_files(diff.files.length)}.');
  } else {
    for (final s in Severity.values) {
      final of = findings.where((f) => f.severity == s).toList();
      if (of.isEmpty) continue;
      b.writeln('\n**${_label(s)}**\n');
      for (final f in of) {
        final where = f.line == null ? f.file : '${f.file}:${f.line}';
        b.writeln('- `$where` — **${f.title}**  \n  ${f.detail}');
      }
    }
  }

  if (diff.truncated.isNotEmpty) {
    b.writeln(
      '\n> Not reviewed, the diff did not fit: '
      '${diff.truncated.map((f) => '`$f`').join(', ')}.',
    );
  }

  b.writeln(
    '\n<sub>$model · ${usage.inputTokens} in, ${usage.outputTokens} out · '
    '\$${costUsd.toStringAsFixed(4)} · '
    '${_files(diff.files.length)} read. A second opinion, not a gate.</sub>',
  );
  return b.toString();
}

String _files(int n) => n == 1 ? '1 file' : '$n files';

String _label(Severity s) => switch (s) {
  Severity.blocker => 'Blockers',
  Severity.risk => 'Risks',
  Severity.nit => 'Nits',
};
