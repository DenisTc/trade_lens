import 'package:dio/dio.dart';

/// CoinGecko Demo API. One demo key is shared by every install (spec,
/// "Ключ CoinGecko"); the header is omitted when the key is empty so the
/// public no-key tier still answers during development.
final class CoinGeckoRestClient {
  CoinGeckoRestClient({required this.dio, this.demoKey = ''});

  static final Uri baseUrl = Uri.parse('https://api.coingecko.com/api/v3/');

  final Dio dio;
  final String demoKey;

  Options get _options =>
      Options(headers: {if (demoKey.isNotEmpty) 'x-cg-demo-api-key': demoKey});

  Future<Map<String, Object?>> simplePrice(
    List<String> ids, {
    String vsCurrency = 'usd',
  }) async {
    final response = await dio.get<Map<String, Object?>>(
      'simple/price',
      queryParameters: {
        'ids': ids.join(','),
        'vs_currencies': vsCurrency,
        'include_24hr_change': 'true',
      },
      options: _options,
    );
    return response.data ?? const {};
  }

  Future<List<Object?>> ohlc(
    String id, {
    required int days,
    String vsCurrency = 'usd',
  }) async {
    final response = await dio.get<List<Object?>>(
      'coins/$id/ohlc',
      queryParameters: {'vs_currency': vsCurrency, 'days': days},
      options: _options,
    );
    return response.data ?? const [];
  }
}
