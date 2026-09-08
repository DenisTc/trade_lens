import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

/// Maps transport failures to domain errors with the 451-vs-timeout
/// distinction the region resolver relies on.
MarketError marketErrorFromDio(String sourceId, DioException e) {
  final status = e.response?.statusCode;
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return MarketError.unavailable(sourceId: sourceId, reason: 'timeout');
    case DioExceptionType.connectionError:
    case DioExceptionType.badCertificate:
      return MarketError.network(
        sourceId: sourceId,
        reason: e.message ?? e.type.name,
      );
    case DioExceptionType.cancel:
      return MarketError.unavailable(sourceId: sourceId, reason: 'cancelled');
    case DioExceptionType.badResponse:
    case DioExceptionType.unknown:
      break;
  }
  return switch (status) {
    451 => MarketError.regionBlocked(sourceId: sourceId),
    429 || 418 => MarketError.rateLimited(
      sourceId: sourceId,
      retryAfter: retryAfterOf(e.response),
    ),
    final s? when s >= 500 => MarketError.unavailable(
      sourceId: sourceId,
      reason: 'http $s',
    ),
    final s? => MarketError.unavailable(sourceId: sourceId, reason: 'http $s'),
    null => MarketError.network(
      sourceId: sourceId,
      reason: e.message ?? 'unknown',
    ),
  };
}

Duration retryAfterOf(Response<Object?>? response) {
  final header = response?.headers.value('retry-after');
  final seconds = header == null ? null : int.tryParse(header);
  return Duration(seconds: seconds ?? 60);
}
