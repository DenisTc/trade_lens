import 'dart:convert';

import 'package:ws_client/ws_client.dart';

/// Bybit's v5 public stream: `{"op": "subscribe", "args": [...]}` in,
/// `{"topic": "...", "type": "snapshot"|"delta", "data": ..., "ts": n}`
/// out, and a `{"op": "ping"}` the client must send every 20 s or the
/// server closes the socket.
///
/// `data` is an object for tickers and the book but an array for klines
/// and trades, so the frame minus its topic is what parsers receive:
/// `{type, data, ts}`. A parser that needs to tell a delta from a
/// snapshot finds `type` there.
final class BybitWsProtocol implements WsProtocol {
  const BybitWsProtocol();

  @override
  String subscribe(List<String> streams, int id) =>
      jsonEncode({'op': 'subscribe', 'args': streams, 'req_id': '$id'});

  @override
  String unsubscribe(List<String> streams, int id) =>
      jsonEncode({'op': 'unsubscribe', 'args': streams, 'req_id': '$id'});

  @override
  ({String stream, Map<String, Object?> data})? decode(
    Map<String, Object?> frame,
  ) {
    final topic = frame['topic'];
    if (topic is! String || !frame.containsKey('data')) return null;
    return (
      stream: topic,
      data: {'type': frame['type'], 'data': frame['data'], 'ts': frame['ts']},
    );
  }

  @override
  String get ping => '{"op":"ping"}';

  @override
  Duration get pingInterval => const Duration(seconds: 20);

  /// Spot allows ten topics per subscribe command.
  @override
  int get maxStreamsPerCommand => 10;
}

/// Topic names of the public spot stream.
String bybitTickerTopic(String symbol) => 'tickers.$symbol';

String bybitKlineTopic(String symbol, String intervalCode) =>
    'kline.$intervalCode.$symbol';

/// Fifty levels, snapshot then deltas; the source keeps the book and
/// shows the top ten.
String bybitBookTopic(String symbol) => 'orderbook.50.$symbol';

String bybitTradeTopic(String symbol) => 'publicTrade.$symbol';
