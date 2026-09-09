import 'dart:async';

import 'package:meta/meta.dart';

/// What comes back from `POST /v1/messages`: the status and the body as a
/// byte stream (SSE when `stream: true`, JSON otherwise).
@immutable
final class ClaudeResponse {
  const ClaudeResponse({
    required this.status,
    required this.body,
    this.headers = const {},
  });

  final int status;
  final Stream<List<int>> body;

  /// Lower-cased header names.
  final Map<String, String> headers;
}

/// Raw HTTP to the Claude API; the app implements it with Dio + SPKI
/// pinning, tests with canned responses, the demo with a recorded stream.
/// The key travels only here, in the `x-api-key` header, never in logs.
abstract interface class ClaudeTransport {
  Future<ClaudeResponse> post(
    Map<String, Object?> body, {
    required String apiKey,
    required CancelSignal cancel,
  });
}

/// Cooperative cancellation: the owner calls [cancel], workers check
/// [isCancelled] or await [whenCancelled].
final class CancelSignal {
  final _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// API constants shared by the real transport and the request builder.
abstract final class ClaudeApi {
  static final Uri baseUrl = Uri.parse('https://api.anthropic.com');
  static const messagesPath = '/v1/messages';
  static const version = '2023-06-01';
}
