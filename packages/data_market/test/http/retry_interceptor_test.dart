import 'package:data_market/data_market.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../support/fake_http_adapter.dart';

void main() {
  final delays = <Duration>[];

  Dio build(FakeHttpAdapter adapter) {
    final dio = createDio(
      baseUrl: Uri.parse('https://example.test'),
      adapter: adapter,
    );
    dio.interceptors
      ..clear()
      ..add(RetryInterceptor(dio: dio, sleep: (d) async => delays.add(d)));
    return dio;
  }

  setUp(delays.clear);

  test('retries 5xx twice with exponential delay, then succeeds', () async {
    final adapter = FakeHttpAdapter(
      (_, i) => i < 2
          ? const FakeResponse(503, '{}')
          : FakeResponse.json({'ok': true}),
    );
    final response = await build(adapter).get<Map<String, Object?>>('/ping');

    expect(response.statusCode, 200);
    expect(adapter.requests, hasLength(3));
    expect(delays, [
      const Duration(milliseconds: 300),
      const Duration(milliseconds: 600),
    ]);
  });

  test('gives up after maxRetries and surfaces the last error', () async {
    final adapter = FakeHttpAdapter((_, _) => const FakeResponse(502, '{}'));

    await expectLater(
      build(adapter).get<Object?>('/ping'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          502,
        ),
      ),
    );
    expect(adapter.requests, hasLength(3));
  });

  test('retries connection errors', () async {
    final adapter = FakeHttpAdapter((options, i) {
      if (i == 0) throw fakeDioError(options, DioExceptionType.connectionError);
      return FakeResponse.json({'ok': true});
    });
    await build(adapter).get<Object?>('/ping');
    expect(adapter.requests, hasLength(2));
  });

  for (final status in [451, 429, 418, 404]) {
    test('does not retry $status', () async {
      final adapter = FakeHttpAdapter((_, _) => FakeResponse(status, '{}'));
      await expectLater(
        build(adapter).get<Object?>('/ping'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requests, hasLength(1));
      expect(delays, isEmpty);
    });
  }
}
