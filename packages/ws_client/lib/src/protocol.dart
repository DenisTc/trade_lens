import 'dart:convert';

/// How one exchange speaks over its socket: the shape of a subscribe
/// command, the shape of a data frame, and whether the client has to ping.
///
/// Everything else — the registry, batching, reconnect, the silence timer
/// — is the same for every exchange, which is what makes a second one a
/// protocol and two parsers rather than a second client.
abstract interface class WsProtocol {
  /// The text to send to start receiving [streams]. [id] is unique per
  /// command, for exchanges that acknowledge by id.
  String subscribe(List<String> streams, int id);

  String unsubscribe(List<String> streams, int id);

  /// The stream name and payload of a data frame, or null for anything
  /// that is not one: acknowledgements, pongs, errors. Only data frames
  /// count as proof the connection is alive.
  ({String stream, Map<String, Object?> data})? decode(
    Map<String, Object?> frame,
  );

  /// A ping the client must send every [pingInterval] to keep the
  /// exchange from closing the socket; null when the transport's own
  /// ping/pong is enough.
  String? get ping;
  Duration? get pingInterval;
}

/// Binance's combined stream: `{"method": "SUBSCRIBE", "params": [...],
/// "id": n}` in, `{"stream": "...", "data": {...}}` out. The runtime
/// answers Binance's transport pings, so the client sends none.
final class BinanceWsProtocol implements WsProtocol {
  const BinanceWsProtocol();

  @override
  String subscribe(List<String> streams, int id) =>
      _command('SUBSCRIBE', streams, id);

  @override
  String unsubscribe(List<String> streams, int id) =>
      _command('UNSUBSCRIBE', streams, id);

  String _command(String method, List<String> params, int id) =>
      jsonEncode({'method': method, 'params': params, 'id': id});

  @override
  ({String stream, Map<String, Object?> data})? decode(
    Map<String, Object?> frame,
  ) {
    final stream = frame['stream'];
    final data = frame['data'];
    if (stream is! String || data is! Map<String, Object?>) return null;
    return (stream: stream, data: data);
  }

  @override
  String? get ping => null;

  @override
  Duration? get pingInterval => null;
}
