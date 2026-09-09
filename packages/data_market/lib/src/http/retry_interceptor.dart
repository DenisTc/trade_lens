import 'dart:async';

import 'package:core/core.dart';
import 'package:dio/dio.dart';

/// Retries transient failures (connection errors, timeouts, 5xx) with a
/// short backoff. Never retries 4xx: 451 is a geo-block decision, 429/418
/// carry their own wait handled by the Binance queue.
final class RetryInterceptor extends Interceptor {
  RetryInterceptor({
    required this.dio,
    this.maxRetries = 2,
    this.baseDelay = const Duration(milliseconds: 300),
    this.logger = const NoopLogger(),
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? Future<void>.delayed;

  final Dio dio;
  final Logger logger;
  final Future<void> Function(Duration) _sleep;
  final int maxRetries;
  final Duration baseDelay;

  static const _attemptKey = 'tl.retry.attempt';

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final attempt = (err.requestOptions.extra[_attemptKey] as int?) ?? 0;
    if (!isRetriable(err) || attempt >= maxRetries) {
      handler.next(err);
      return;
    }
    final delay = baseDelay * (1 << attempt);
    logger.warn(
      'retry ${attempt + 1}/$maxRetries ${err.requestOptions.uri} in $delay',
      err.type,
    );
    await _sleep(delay);
    err.requestOptions.extra[_attemptKey] = attempt + 1;
    try {
      final response = await dio.fetch<Object?>(err.requestOptions);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  static bool isRetriable(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final status = err.response?.statusCode ?? 0;
        return status >= 500 && status < 600;
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.unknown:
        return false;
    }
  }
}
