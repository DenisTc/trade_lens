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
  ///
  /// Both halves matter: the marker, and that a bot wrote it. A person
  /// who quotes the marker in a comment of their own must never have it
  /// overwritten. A run outside Actions, with someone's personal token,
  /// therefore leaves a new comment each time rather than risking that.
  Future<int?> _mine() async {
    const perPage = 100;
    for (var page = 1; page <= _maxPages; page++) {
      final list = await _send(
        'GET',
        '/repos/$repository/issues/$pullRequest/comments'
            '?per_page=$perPage&page=$page',
        null,
      );
      if (list is! List) return null;
      for (final c in list.reversed) {
        if (c is! Map<String, Object?> || c['id'] is! int) continue;
        final body = c['body'];
        final user = c['user'];
        final isBot = user is Map<String, Object?> && user['type'] == 'Bot';
        if (isBot && body is String && body.contains(commentMarker)) {
          return c['id']! as int;
        }
      }
      if (list.length < perPage) return null;
    }
    return null;
  }

  /// Ten pages of comments is a thousand: past that, a duplicate review
  /// is a smaller problem than the time spent looking for the old one.
  static const _maxPages = 10;

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
