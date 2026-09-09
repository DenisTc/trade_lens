import 'dart:async';

import 'package:ai_insights/ai_insights.dart';
import 'package:core/core.dart';
import 'package:data_market/src/http/dio_factory.dart';
import 'package:data_market/src/http/pins.dart';
import 'package:data_market/src/http/spki_preflight.dart';
import 'package:dio/dio.dart';

/// `POST /v1/messages` over the app's Dio.
///
/// What protects the user's key, in order:
///
/// - a pinned TLS handshake runs *before* the request (Dio validates the
///   certificate only once the response is in, which would be after the
///   key left the device); a mismatch fails the call with nothing sent;
/// - redirects are refused, so a 3xx cannot forward `x-api-key` to
///   another host;
/// - the key is passed per call and set only on that header, never on the
///   base options, so it cannot reach logs or Sentry breadcrumbs built
///   from the Dio configuration;
/// - no retries: a re-sent summary would be billed twice.
final class DioClaudeTransport implements ClaudeTransport {
  DioClaudeTransport({
    Dio? dio,
    SpkiPreflight? preflight,
    Logger logger = const NoopLogger(),
  }) : _preflight = preflight ?? SpkiPreflight(pins: tradeLensPins),
       _dio =
           dio ??
           createDio(
             baseUrl: ClaudeApi.baseUrl,
             pins: tradeLensPins,
             logger: logger,
             // A summary streams for a while; the socket must not time out
             // between deltas.
             timeout: const Duration(seconds: 60),
             retries: 0,
             headers: const {
               'anthropic-version': ClaudeApi.version,
               'content-type': 'application/json',
             },
           );

  final Dio _dio;
  final SpkiPreflight _preflight;

  @override
  Future<ClaudeResponse> post(
    Map<String, Object?> body, {
    required String apiKey,
    required CancelSignal cancel,
  }) async {
    final host = ClaudeApi.baseUrl.host;
    if (!await _preflight.verify(host)) {
      throw AiError.network('$host did not present its pinned key');
    }
    if (cancel.isCancelled) throw const AiError.cancelled();

    final token = CancelToken();
    // Stays alive until the body is done: cancelling after the headers
    // arrived must still abort the stream.
    final subscription = cancel.whenCancelled.asStream().listen(
      (_) => token.cancel('cancelled by the caller'),
    );
    try {
      final response = await _dio.post<ResponseBody>(
        ClaudeApi.messagesPath,
        data: body,
        cancelToken: token,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'x-api-key': apiKey},
          // Errors are read from the body, not thrown as DioException.
          validateStatus: (_) => true,
          // A redirect would resend the key to whatever Location says.
          followRedirects: false,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status >= 300 && status < 400) {
        unawaited(subscription.cancel());
        throw const AiError.badRequest('the API answered with a redirect');
      }
      final stream = response.data?.stream;
      return ClaudeResponse(
        status: status,
        body: stream == null
            ? const Stream<List<int>>.empty()
            : _untilDone(stream, cancel, subscription.cancel),
        headers: {
          for (final entry in response.headers.map.entries)
            entry.key.toLowerCase(): entry.value.join(','),
        },
      );
    } on DioException catch (e) {
      unawaited(subscription.cancel());
      if (CancelToken.isCancel(e) || cancel.isCancelled) {
        throw const AiError.cancelled();
      }
      throw AiError.network(e.message ?? e.type.name);
    } on Object {
      unawaited(subscription.cancel());
      rethrow;
    }
  }

  /// Releases [cleanup] when the body ends, fails or is cancelled, and
  /// gives a mid-stream failure the same typed shape as a failure before
  /// the headers arrived.
  static Stream<List<int>> _untilDone(
    Stream<List<int>> source,
    CancelSignal cancel,
    Future<void> Function() cleanup,
  ) async* {
    try {
      yield* source;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e) || cancel.isCancelled) {
        throw const AiError.cancelled();
      }
      throw AiError.network(e.message ?? e.type.name);
    } finally {
      await cleanup();
    }
  }
}
