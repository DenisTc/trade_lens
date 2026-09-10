import 'dart:convert';
import 'dart:io';

import 'package:ai_insights/ai_insights.dart';

/// The Claude transport for a CI runner: `dart:io`, no pinning.
///
/// The app pins the API's key, because it runs on a phone on somebody
/// else's network; a GitHub runner talks to the same host over the same
/// TLS with the platform's trust store, and a pin there would only be a
/// second thing to rotate.
final class IoClaudeTransport implements ClaudeTransport {
  IoClaudeTransport({HttpClient? client, Duration? timeout})
    : _client = client ?? HttpClient(),
      _timeout = timeout ?? const Duration(seconds: 120);

  final HttpClient _client;
  final Duration _timeout;

  @override
  Future<ClaudeResponse> post(
    Map<String, Object?> body, {
    required String apiKey,
    required CancelSignal cancel,
  }) async {
    final request = await _client
        .postUrl(ClaudeApi.baseUrl.replace(path: ClaudeApi.messagesPath))
        .timeout(_timeout);
    request.followRedirects = false;
    request.headers
      ..set('content-type', 'application/json')
      ..set('anthropic-version', ClaudeApi.version)
      ..set('x-api-key', apiKey);
    request.add(utf8.encode(jsonEncode(body)));

    final response = await request.close().timeout(_timeout);
    return ClaudeResponse(
      status: response.statusCode,
      body: response,
      headers: {
        for (final name in const ['request-id', 'retry-after'])
          name: ?response.headers.value(name),
      },
    );
  }

  void close() => _client.close(force: true);
}
