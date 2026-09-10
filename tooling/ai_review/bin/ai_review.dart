import 'dart:convert';
import 'dart:io';

import 'package:ai_insights/ai_insights.dart';
import 'package:ai_review/ai_review.dart';
import 'package:core/core.dart';

/// Reviews a pull request and leaves one comment on it.
///
/// Everything comes from the environment GitHub Actions already sets:
///
///   ANTHROPIC_API_KEY   the key the review is billed to
///   GITHUB_TOKEN        the token the comment is posted with
///   GITHUB_REPOSITORY   owner/name
///   GITHUB_EVENT_PATH   the event payload, for the number and the base
///   TL_AI_REVIEW_MODEL  optional model config JSON, same shape as the
///                       app's `ai_model` in Remote Config
///
/// Without a key it prints why and exits 0: a fork has no business
/// failing because it cannot pay for a review.
Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final key = env['ANTHROPIC_API_KEY'];
  if (key == null || key.isEmpty) {
    stdout.writeln('No ANTHROPIC_API_KEY; skipping the review.');
    return;
  }

  final event = _event(env['GITHUB_EVENT_PATH']);
  final number = _int(event?['number']) ?? _int(args.firstOrNull);
  final repository = env['GITHUB_REPOSITORY'];
  final token = env['GITHUB_TOKEN'];
  if (number == null || repository == null || token == null) {
    stderr.writeln(
      'Need GITHUB_REPOSITORY, GITHUB_TOKEN and a pull request number.',
    );
    exitCode = 2;
    return;
  }

  final pr = event?['pull_request'];
  final base = pr is Map<String, Object?> ? pr['base'] : null;
  final baseSha = base is Map<String, Object?> ? base['sha'] as String? : null;
  final diff = selectDiff(await _diff(baseSha ?? 'origin/main'));
  if (diff.isEmpty) {
    stdout.writeln('Nothing to review: the diff has no reviewable file.');
    return;
  }
  stdout.writeln('Reviewing ${diff.files.length} file(s).');

  final config = AiModelConfig.parse(env['TL_AI_REVIEW_MODEL']);
  final transport = IoClaudeTransport();
  final comments = GitHubComments(
    repository: repository,
    pullRequest: number,
    apiToken: token,
  );
  try {
    final response = await transport.post(
      reviewRequest(
        diff,
        config: config,
        title: pr is Map<String, Object?> ? pr['title'] as String? : null,
        description: pr is Map<String, Object?> ? pr['body'] as String? : null,
      ),
      apiKey: key,
      cancel: CancelSignal(),
    );
    final body = await response.body.transform(utf8.decoder).join();
    if (response.status != 200) {
      stderr.writeln('The API answered ${response.status}: ${_head(body)}');
      exitCode = 1;
      return;
    }

    switch (parseMessage(body)) {
      case Err(:final error):
        stderr.writeln('Unusable response: $error');
        exitCode = 1;
      case Ok(:final value):
        if (value.stopReason == 'max_tokens') {
          stderr.writeln(
            'The answer hit max_tokens; raising maxOutputTokens would help.',
          );
        }
        switch (ReviewFindings.parse(value.text)) {
          case Err(:final error):
            stderr.writeln('Unusable findings: $error\n${_head(value.text)}');
            exitCode = 1;
          case Ok(value: final findings):
            final comment = renderComment(
              findings,
              diff: diff,
              model: config.model,
              usage: value.usage,
              costUsd: config.costUsd(
                inputTokens: value.usage.inputTokens,
                outputTokens: value.usage.outputTokens,
              ),
            );
            await comments.post(comment);
            stdout.writeln(comment);
            await _summary(comment);
        }
    }
  } on AiError catch (e) {
    stderr.writeln('The review call failed: $e');
    exitCode = 1;
  } finally {
    transport.close();
    comments.close();
  }
}

/// `git diff base...HEAD`: what this branch changed, not what happened on
/// the base since it forked.
Future<String> _diff(String base) async {
  final result = await Process.run('git', [
    'diff',
    '--unified=3',
    '--no-color',
    '$base...HEAD',
  ]);
  if (result.exitCode != 0) {
    stderr.writeln('git diff failed: ${result.stderr}');
    return '';
  }
  return result.stdout as String;
}

Map<String, Object?>? _event(String? path) {
  if (path == null || !File(path).existsSync()) return null;
  final decoded = jsonDecode(File(path).readAsStringSync());
  return decoded is Map<String, Object?> ? decoded : null;
}

Future<void> _summary(String comment) async {
  final path = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (path == null) return;
  await File(path).writeAsString('$comment\n', mode: FileMode.append);
}

int? _int(Object? v) => v is int ? v : int.tryParse('${v ?? ''}');

String _head(String s) => s.length > 400 ? '${s.substring(0, 400)}…' : s;
