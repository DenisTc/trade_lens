import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Canned response for one request.
final class FakeResponse {
  const FakeResponse(this.statusCode, this.body, {this.headers = const {}});

  factory FakeResponse.json(
    Object body, {
    int status = 200,
    Map<String, String> headers = const {},
  }) => FakeResponse(status, jsonEncode(body), headers: headers);

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

/// Records every request and answers from a script. No live network in
/// tests (spec, "Тесты"). A handler may throw a [DioException] to simulate
/// timeouts and connection errors.
final class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this._handler);

  final FakeResponse Function(RequestOptions options, int callIndex) _handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = requests.length;
    requests.add(options);
    final response = _handler(options, index);
    return ResponseBody.fromString(
      response.body,
      response.statusCode,
      headers: {
        'content-type': ['application/json'],
        for (final e in response.headers.entries)
          e.key.toLowerCase(): [e.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Convenience: a `DioException` of the given type for the handler to throw.
DioException fakeDioError(RequestOptions options, DioExceptionType type) =>
    DioException(requestOptions: options, type: type, message: type.name);
