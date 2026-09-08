import 'package:core/core.dart';
import 'package:data_market/src/http/retry_interceptor.dart';
import 'package:data_market/src/http/spki_pinning.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// One place that knows how a TradeLens HTTP client is assembled:
/// timeouts, SPKI pinning on top of normal chain validation, retry and
/// logging. Everything else receives a ready [Dio].
Dio createDio({
  required Uri baseUrl,
  PinSet? pins,
  Logger logger = const NoopLogger(),
  Duration timeout = const Duration(seconds: 10),
  Map<String, String> headers = const {},
  HttpClientAdapter? adapter,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl.toString(),
      connectTimeout: timeout,
      receiveTimeout: timeout,
      sendTimeout: timeout,
      headers: headers,
    ),
  );
  dio
    ..httpClientAdapter =
        adapter ??
        IOHttpClientAdapter(
          validateCertificate: pins == null
              ? null
              : (certificate, host, port) =>
                    validatePinnedCertificate(pins, certificate, host),
        )
    ..interceptors.add(RetryInterceptor(dio: dio, logger: logger));
  return dio;
}
