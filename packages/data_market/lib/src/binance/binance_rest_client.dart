import 'dart:convert';

import 'package:data_market/src/binance/binance_request_queue.dart';
import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

/// Thin typed wrapper over the three public endpoints we use. Weights are
/// the documented request weights (2026-09) and feed the queue.
final class BinanceRestClient {
  BinanceRestClient({required this._dio, BinanceRequestQueue? queue})
    : _queue = queue ?? BinanceRequestQueue();

  final Dio _dio;
  final BinanceRequestQueue _queue;

  /// `GET /ping` — weight 1. Used by the region probe.
  Future<void> ping() =>
      _queue.run(1, () => _dio.get<Map<String, Object?>>('ping'));

  /// `GET /ticker/24hr?symbols=[...]` — weight 2 for up to 20 symbols,
  /// 40 up to 100.
  Future<List<Map<String, Object?>>> ticker24h(List<String> symbols) async {
    final weight = symbols.length <= 20 ? 2 : 40;
    final response = await _queue.run(
      weight,
      () => _dio.get<List<Object?>>(
        'ticker/24hr',
        queryParameters: {'symbols': jsonEncode(symbols)},
      ),
    );
    return (response.data ?? const []).cast<Map<String, Object?>>();
  }

  /// `GET /klines?symbol&interval&limit` — weight 2.
  Future<List<List<Object?>>> klines(
    String symbol,
    Interval interval, {
    int limit = 500,
    DateTime? startTime,
  }) async {
    final response = await _queue.run(
      2,
      () => _dio.get<List<Object?>>(
        'klines',
        queryParameters: {
          'symbol': symbol,
          'interval': interval.code,
          'limit': limit,
          if (startTime != null)
            'startTime': startTime.toUtc().millisecondsSinceEpoch,
        },
      ),
    );
    return (response.data ?? const []).cast<List<Object?>>();
  }
}
