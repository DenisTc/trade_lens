import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_review/ai_review.dart';
import 'package:test/test.dart';

/// A GitHub stand-in: records what it was asked and answers what it was
/// told to.
final class FakeGitHub {
  FakeGitHub(this._comments);

  final List<Map<String, Object?>> _comments;
  final requests = <({String method, String path, Object? body})>[];
  late final HttpServer _server;

  Uri get api => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_serve());
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      final body = await utf8.decoder.bind(request).join();
      requests.add((
        method: request.method,
        path: request.uri.path,
        body: body.isEmpty ? null : jsonDecode(body),
      ));
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(request.method == 'GET' ? jsonEncode(_comments) : '{}');
      await request.response.close();
    }
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late FakeGitHub github;

  Future<void> post(String body, List<Map<String, Object?>> existing) async {
    github = FakeGitHub(existing);
    await github.start();
    final comments = GitHubComments(
      repository: 'DenisTc/trade_lens',
      pullRequest: 42,
      apiToken: 'token',
      api: github.api,
    );
    await comments.post(body);
    comments.close();
  }

  tearDown(() => github.stop());

  test('the first review is a new comment', () async {
    await post('hello $commentMarker', const []);

    expect(github.requests.last.method, 'POST');
    expect(
      github.requests.last.path,
      '/repos/DenisTc/trade_lens/issues/42/comments',
    );
  });

  test('a rerun replaces its own comment instead of adding one', () async {
    await post('second $commentMarker', [
      {'id': 1, 'body': 'a human said something'},
      {'id': 2, 'body': 'an older review $commentMarker'},
    ]);

    expect(github.requests.last.method, 'PATCH');
    expect(
      github.requests.last.path,
      '/repos/DenisTc/trade_lens/issues/comments/2',
    );
    expect(
      (github.requests.last.body! as Map)['body'],
      'second $commentMarker',
    );
  });

  test('a human comment is never edited', () async {
    await post('review $commentMarker', [
      {'id': 1, 'body': 'looks good to me'},
    ]);

    expect(github.requests.last.method, 'POST');
  });
}
