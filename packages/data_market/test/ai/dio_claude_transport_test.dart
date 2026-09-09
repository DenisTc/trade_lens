import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_insights/ai_insights.dart';
import 'package:data_market/data_market.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// Answers with a canned [ResponseBody] and records what Dio handed it.
final class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  RequestOptions? last;
  Future<void>? cancelFuture;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    last = options;
    this.cancelFuture = cancelFuture;
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  /// No pins for the host, so the preflight passes without a handshake.
  SpkiPreflight openPreflight() => SpkiPreflight(pins: const PinSet({}));

  DioClaudeTransport transport(_FakeAdapter adapter, {SpkiPreflight? pins}) {
    final dio = Dio(BaseOptions(baseUrl: ClaudeApi.baseUrl.toString()))
      ..httpClientAdapter = adapter;
    return DioClaudeTransport(dio: dio, preflight: pins ?? openPreflight());
  }

  ResponseBody sse(String body, {int status = 200}) => ResponseBody.fromString(
    body,
    status,
    headers: {
      'content-type': ['text/event-stream'],
      'Retry-After': ['7'],
    },
  );

  test('sends the key only on x-api-key and streams the body back', () async {
    final adapter = _FakeAdapter((_) => sse('event: ping\ndata: {}\n\n'));
    final client = transport(adapter);

    final response = await client.post(
      {'model': 'claude-test'},
      apiKey: 'sk-ant-secret',
      cancel: CancelSignal(),
    );

    expect(response.status, 200);
    expect(await utf8.decodeStream(response.body), contains('event: ping'));
    expect(adapter.last!.headers['x-api-key'], 'sk-ant-secret');
    // The key must not survive on the client for the next request.
    expect(
      adapter.last!.headers.entries
          .where((e) => e.key != 'x-api-key')
          .map((e) => '${e.value}')
          .join(),
      isNot(contains('sk-ant-secret')),
    );
    expect(response.headers['retry-after'], '7');
  });

  test('refuses a redirect instead of resending the key', () async {
    final adapter = _FakeAdapter(
      (_) => ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['https://evil.example/v1/messages'],
        },
      ),
    );
    await expectLater(
      transport(adapter)
          .post(const {}, apiKey: 'sk-ant-secret', cancel: CancelSignal()),
      throwsA(isA<AiBadRequest>()),
    );
    expect(adapter.last!.followRedirects, isFalse);
  });

  test('a pin mismatch sends nothing at all', () async {
    final adapter = _FakeAdapter((_) => sse(''));
    final blocked = SpkiPreflight(
      pins: const PinSet({
        'api.anthropic.com': {'not-the-real-pin'},
      }),
      handshake: (_, _) async => null,
    );

    await expectLater(
      transport(
        adapter,
        pins: blocked,
      ).post(const {}, apiKey: 'sk-ant-secret', cancel: CancelSignal()),
      throwsA(isA<AiNetwork>()),
    );
    expect(adapter.calls, 0, reason: 'the request never left');
  });

  test('cancelling after the headers still aborts the request', () async {
    // A body that never ends: only cancellation can stop it.
    final adapter = _FakeAdapter(
      (_) => ResponseBody(
        StreamController<Uint8List>().stream,
        200,
        headers: {
          'content-type': ['text/event-stream'],
        },
      ),
    );
    final cancel = CancelSignal();
    final response = await transport(adapter)
        .post(const {}, apiKey: 'sk-ant-secret', cancel: cancel);
    final drained = response.body.drain<void>();

    cancel.cancel();
    await expectLater(
      adapter.cancelFuture!.catchError((Object _) {}),
      completes,
    );
    // Dio propagates the cancellation into the body stream.
    await expectLater(drained.catchError((Object _) {}), completes);
  });

  test('a transport failure becomes a typed network error', () async {
    final dio = Dio(BaseOptions(baseUrl: ClaudeApi.baseUrl.toString()))
      ..httpClientAdapter = _ThrowingAdapter();
    await expectLater(
      DioClaudeTransport(
        dio: dio,
        preflight: openPreflight(),
      ).post(const {}, apiKey: 'sk-ant-secret', cancel: CancelSignal()),
      throwsA(isA<AiNetwork>()),
    );
  });
}

final class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw const SocketException('no route to host');

  @override
  void close({bool force = false}) {}
}
