import 'dart:convert';
import 'dart:io';

import 'package:ai_review/src/comment.dart';

/// The one thing the reviewer writes: a comment on a pull request.
///
/// It replaces its own comment instead of adding one per push, so a
/// branch with twenty commits carries one review, not twenty.
final class GitHubComments {
  GitHubComments({
    required this.repository,
    required this.pullRequest,
    required String apiToken,
    HttpClient? client,
    Uri? api,
  }) : _token = apiToken,
       _client = client ?? HttpClient(),
       _api = api ?? Uri.parse('https://api.github.com');

  /// `owner/name`, as GitHub Actions puts it in `GITHUB_REPOSITORY`.
  final String repository;
  final int pullRequest;
  final String _token;
  final HttpClient _client;
  final Uri _api;

  Future<void> post(String body) async {
    final existing = await _mine();
    if (existing == null) {
      await _send('POST', '/repos/$repository/issues/$pullRequest/comments', {
        'body': body,
      });
    } else {
      await _send('PATCH', '/repos/$repository/issues/comments/$existing', {
        'body': body,
      });
    }
  }

  /// The id of the comment a previous run left, if it is still there.
  Future<int?> _mine() async {
    final list = await _send(
      'GET',
      '/repos/$repository/issues/$pullRequest/comments?per_page=100',
      null,
    );
    if (list is! List) return null;
    for (final c in list.reversed) {
      if (c is Map<String, Object?> &&
          c['body'] is String &&
          (c['body']! as String).contains(commentMarker) &&
          c['id'] is int) {
        return c['id']! as int;
      }
    }
    return null;
  }

  Future<Object?> _send(String method, String path, Object? body) async {
    final request = await _client.openUrl(
      method,
      _api.replace(path: path.split('?').first, query: _queryOf(path)),
    );
    request.headers
      ..set('accept', 'application/vnd.github+json')
      ..set('authorization', 'Bearer $_token')
      ..set('user-agent', 'tradelens-ai-review');
    if (body != null) {
      request.headers.set('content-type', 'application/json');
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      throw HttpException(
        'GitHub answered ${response.statusCode}: '
        '${text.length > 300 ? '${text.substring(0, 300)}…' : text}',
      );
    }
    return text.isEmpty ? null : jsonDecode(text);
  }

  static String? _queryOf(String path) {
    final i = path.indexOf('?');
    return i < 0 ? null : path.substring(i + 1);
  }

  void close() => _client.close(force: true);
}
