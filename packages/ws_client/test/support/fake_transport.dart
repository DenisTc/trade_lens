import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ws_client/ws_client.dart';

/// Scripted transport: every `connect` yields a [FakeConnection] the test
/// can feed frames into or drop, unless [failNextConnects] is positive.
final class FakeTransport implements WsTransport {
  final List<FakeConnection> connections = [];
  final List<Uri> attempts = [];
  int failNextConnects = 0;

  FakeConnection get last => connections.last;

  @override
  Future<WsConnection> connect(Uri url) async {
    attempts.add(url);
    if (failNextConnects > 0) {
      failNextConnects--;
      throw const SocketException('refused');
    }
    final connection = FakeConnection();
    connections.add(connection);
    return connection;
  }
}

final class FakeConnection implements WsConnection {
  final StreamController<String> _incoming = StreamController<String>();
  final List<String> sent = [];
  bool closed = false;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String text) => sent.add(text);

  @override
  Future<void> close() async {
    closed = true;
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  /// Server pushes a frame.
  void push(Object json) => _incoming.add(jsonEncode(json));

  void pushRaw(String text) => _incoming.add(text);

  /// Server drops the connection.
  void drop() => unawaited(_incoming.close());

  /// Parsed commands sent so far, e.g. `{method: SUBSCRIBE, params: [...]}`.
  List<Map<String, Object?>> get commands => [
    for (final text in sent) jsonDecode(text) as Map<String, Object?>,
  ];
}

/// Deterministic jitter: always the midpoint, i.e. no jitter.
final class NoJitter implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0.5;

  @override
  int nextInt(int max) => 0;
}
