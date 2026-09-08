import 'dart:async';
import 'dart:io';

/// Opens [url], waits for the first data frame within [timeout], closes.
/// True only if data arrived: an open socket that never speaks is what a
/// half-open connection looks like, and the probe must not count it.
typedef WsHandshake = Future<bool> Function(Uri url, Duration timeout);

Future<bool> ioWsHandshake(Uri url, Duration timeout) async {
  WebSocket? socket;
  try {
    socket = await WebSocket.connect(url.toString()).timeout(timeout);
    await socket.first.timeout(timeout);
    return true;
  } on Object {
    return false;
  } finally {
    unawaited(socket?.close());
  }
}
