import 'package:dio/dio.dart';

/// Bybit answers every request with the same envelope: `retCode` 0 and a
/// `result`, or a code and a message. Anything but 0 is this.
final class BybitApiException implements Exception {
  const BybitApiException(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => 'BybitApiException($code: $message)';
}

/// Thin Dio wrapper over the v5 market endpoints; returns `result`
/// objects, leaves parsing to `bybit_parsers.dart`.
final class BybitRestClient {
  BybitRestClient({required this._dio});

  final Dio _dio;

  /// `GET market/time`: the probe's ping.
  static Uri ping(Uri base) => base.resolve('market/time');

  /// `GET market/kline`. Bybit lists rows newest first and takes `end` as
  /// an inclusive upper bound on the open time.
  Future<List<Object?>> kline(
    String symbol,
    String intervalCode, {
    int limit = 500,
    DateTime? end,
  }) async {
    final result = await _get('market/kline', {
      'category': 'spot',
      'symbol': symbol,
      'interval': intervalCode,
      'limit': limit,
      if (end != null) 'end': end.toUtc().millisecondsSinceEpoch,
    });
    return _list(result['list'], 'list');
  }

  /// `GET market/tickers` for the whole spot market: Bybit takes one
  /// symbol per call or none, and the catalog is twenty pairs, so one
  /// call and a filter beats twenty calls.
  Future<List<Object?>> tickers() async {
    final result = await _get('market/tickers', {'category': 'spot'});
    return _list(result['list'], 'list');
  }

  Future<Map<String, Object?>> _get(
    String path,
    Map<String, Object?> query,
  ) async {
    final response = await _dio.get<Map<String, Object?>>(
      path,
      queryParameters: query,
    );
    final body = response.data;
    if (body == null) throw const FormatException('empty body');
    final code = body['retCode'];
    if (code is! int) throw FormatException('no retCode in $body');
    if (code != 0) {
      throw BybitApiException(code, '${body['retMsg'] ?? 'no message'}');
    }
    final result = body['result'];
    if (result is! Map<String, Object?>) {
      throw FormatException('result is not an object: $result');
    }
    return result;
  }

  static List<Object?> _list(Object? value, String field) {
    if (value is! List<Object?>) {
      throw FormatException('$field is not an array: $value');
    }
    return value;
  }
}
