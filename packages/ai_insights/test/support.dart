import 'dart:async';
import 'dart:convert';

import 'package:ai_insights/ai_insights.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';

/// Builds an SSE body from typed events, the way the API emits them.
String sse(List<Map<String, Object?>> events) =>
    events.map((e) => 'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n').join();

List<Map<String, Object?>> textTurn(
  String text, {
  String stopReason = 'end_turn',
  int inputTokens = 100,
  int outputTokens = 20,
}) => [
  {
    'type': 'message_start',
    'message': {
      'usage': {'input_tokens': inputTokens, 'output_tokens': 1},
    },
  },
  {
    'type': 'content_block_start',
    'index': 0,
    'content_block': {'type': 'text', 'text': ''},
  },
  for (final piece in text.split(' '))
    {
      'type': 'content_block_delta',
      'index': 0,
      'delta': {'type': 'text_delta', 'text': '$piece '},
    },
  {'type': 'content_block_stop', 'index': 0},
  {
    'type': 'message_delta',
    'delta': {'stop_reason': stopReason},
    'usage': {'output_tokens': outputTokens},
  },
  {'type': 'message_stop'},
];

List<Map<String, Object?>> toolTurn(
  String name,
  Map<String, Object?> input, {
  String id = 'toolu_1',
  String preface = '',
}) => [
  {
    'type': 'message_start',
    'message': {
      'usage': {'input_tokens': 200, 'output_tokens': 1},
    },
  },
  if (preface.isNotEmpty) ...[
    {
      'type': 'content_block_start',
      'index': 0,
      'content_block': {'type': 'text', 'text': ''},
    },
    {
      'type': 'content_block_delta',
      'index': 0,
      'delta': {'type': 'text_delta', 'text': preface},
    },
    {'type': 'content_block_stop', 'index': 0},
  ],
  {
    'type': 'content_block_start',
    'index': 1,
    'content_block': {
      'type': 'tool_use',
      'id': id,
      'name': name,
      'input': <String, Object?>{},
    },
  },
  // Input JSON arrives in pieces.
  for (final piece in _split(jsonEncode(input), 7))
    {
      'type': 'content_block_delta',
      'index': 1,
      'delta': {'type': 'input_json_delta', 'partial_json': piece},
    },
  {'type': 'content_block_stop', 'index': 1},
  {
    'type': 'message_delta',
    'delta': {'stop_reason': 'tool_use'},
    'usage': {'output_tokens': 30},
  },
  {'type': 'message_stop'},
];

List<String> _split(String s, int n) => [
  for (var i = 0; i < s.length; i += n)
    s.substring(i, (i + n).clamp(0, s.length)),
];

/// Scripted responses, one per request, in order. Records the bodies.
final class FakeTransport implements ClaudeTransport {
  FakeTransport(this.responses);

  final List<ClaudeResponse Function(Map<String, Object?> body)> responses;
  final requests = <Map<String, Object?>>[];
  final keys = <String>[];

  @override
  Future<ClaudeResponse> post(
    Map<String, Object?> body, {
    required String apiKey,
    required CancelSignal cancel,
  }) async {
    requests.add(body);
    keys.add(apiKey);
    if (requests.length > responses.length) {
      throw StateError('no scripted response for request ${requests.length}');
    }
    return responses[requests.length - 1](body);
  }
}

ClaudeResponse ok(String body, {int chunk = 11}) => ClaudeResponse(
  status: 200,
  body: Stream.fromIterable([
    for (var i = 0; i < body.length; i += chunk)
      utf8.encode(body.substring(i, (i + chunk).clamp(0, body.length))),
  ]),
);

ClaudeResponse http(int status, String body, {Map<String, String>? headers}) =>
    ClaudeResponse(
      status: status,
      body: Stream.value(utf8.encode(body)),
      headers: headers ?? const {},
    );

final btc = Instrument(
  symbol: 'BTCUSDT',
  base: defaultAssets.first,
  quote: 'USDT',
  sourceId: 'fake',
);

final class FakeTools implements MarketTools {
  FakeTools({this.book = true});

  final bool book;
  final calls = <String>[];

  @override
  List<Instrument> get instruments => [btc];

  @override
  String get sourceName => 'Fake Exchange';

  @override
  Set<Interval> get intervals => {Interval.m15, Interval.h1};

  @override
  Future<List<Candle>> klines(
    Instrument instrument,
    Interval interval,
    int limit,
  ) async {
    calls.add('klines ${instrument.symbol} ${interval.code} $limit');
    return [
      for (var i = 0; i < limit.clamp(0, 3); i++)
        Candle(
          openTime: DateTime.utc(2026, 9, 9, i),
          open: Decimal.parse('100'),
          high: Decimal.parse('101'),
          low: Decimal.parse('99'),
          close: Decimal.parse('100.5'),
          volume: Decimal.parse('12.5'),
        ),
    ];
  }

  @override
  Future<OrderBookSnapshot?> orderBook(Instrument instrument) async {
    calls.add('book ${instrument.symbol}');
    if (!book) return null;
    return OrderBookSnapshot(
      instrument: instrument,
      bids: [OrderBookLevel(price: Decimal.parse('100'), qty: Decimal.one)],
      asks: [
        OrderBookLevel(price: Decimal.parse('101'), qty: Decimal.fromInt(2)),
      ],
      at: DateTime.utc(2026, 9, 9, 12),
    );
  }
}
