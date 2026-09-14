import 'dart:async';
import 'dart:io';

/// Outcome of a WebSocket probe.
enum WsProbeResult {
  /// Connected and received a data frame within the deadline.
  alive,

  /// No connection or no frame within the deadline: half-open or down.
  silent,

  /// The upgrade request was answered with HTTP 451.
  blocked,
}

/// Opens [url], sends [send] when given, waits for the first frame after
/// it, closes. One shared [timeout] covers connect + first frame. An open
/// socket that never speaks is what a half-open connection looks like,
/// and the probe must not count it as alive.
///
/// [send] exists for exchanges that stay silent until subscribed: Binance
/// takes the subscription in the URL, Bybit wants a command.
typedef WsHandshake = Future<WsProbeResult> Function(
  Uri url,
  Duration timeout, {
  String? send,
});

Future<WsProbeResult> ioWsHandshake(
  Uri url,
  Duration timeout, {
  String? send,
}) async {
  final stopwatch = Stopwatch()..start();
  final connecting = WebSocket.connect(url.toString());
  WebSocket? socket;
  try {
    socket = await connecting.timeout(
      timeout,
      onTimeout: () {
        // A late connection must not leak: close it when it finally opens.
        unawaited(connecting.then((s) => s.close(), onError: (Object _) {}));
        throw TimeoutException('ws connect', timeout);
      },
    );
    final remaining = timeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) return WsProbeResult.silent;
    if (send != null) socket.add(send);
    // An acknowledgement is a frame too, and enough: it proves the socket
    // carries data both ways, which is what a half-open one cannot.
    await socket.first.timeout(remaining);
    return WsProbeResult.alive;
  } on WebSocketException catch (e) {
    return e.httpStatusCode == 451
        ? WsProbeResult.blocked
        : WsProbeResult.silent;
  } on Object {
    return WsProbeResult.silent;
  } finally {
    unawaited(socket?.close());
  }
}
