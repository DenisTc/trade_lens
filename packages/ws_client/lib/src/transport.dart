import 'dart:async';
import 'dart:io';

/// A live socket. [messages] completes when the peer closes or the
/// connection breaks; errors are reported through the same stream.
abstract interface class WsConnection {
  Stream<String> get messages;
  void send(String text);
  Future<void> close();
}

/// Opens connections. The client never touches `dart:io` directly so tests
/// can drive a fake and the layer stays testable with a fake clock.
abstract interface class WsTransport {
  Future<WsConnection> connect(Uri url);
}

/// `dart:io` implementation. Transport-level ping/pong is handled by the
/// runtime and never surfaces here, which is exactly why the client needs
/// its own silence detection.
final class IoWsTransport implements WsTransport {
  const IoWsTransport({this.connectTimeout = const Duration(seconds: 10)});

  final Duration connectTimeout;

  @override
  Future<WsConnection> connect(Uri url) async {
    final socket = await WebSocket.connect(url.toString())
        .timeout(connectTimeout);
    return _IoConnection(socket);
  }
}

final class _IoConnection implements WsConnection {
  _IoConnection(this._socket);

  final WebSocket _socket;

  @override
  Stream<String> get messages =>
      _socket.where((frame) => frame is String).cast<String>();

  @override
  void send(String text) => _socket.add(text);

  @override
  Future<void> close() => _socket.close();
}
