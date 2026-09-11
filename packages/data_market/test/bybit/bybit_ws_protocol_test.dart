import 'dart:convert';

import 'package:data_market/data_market.dart';
import 'package:test/test.dart';

void main() {
  const protocol = BybitWsProtocol();

  test('subscribe and unsubscribe carry the topics and a request id', () {
    expect(jsonDecode(protocol.subscribe(['tickers.BTCUSDT'], 7)), {
      'op': 'subscribe',
      'args': ['tickers.BTCUSDT'],
      'req_id': '7',
    });
    final unsubscribe =
        jsonDecode(protocol.unsubscribe(['a', 'b'], 8)) as Map<String, Object?>;
    expect(unsubscribe['op'], 'unsubscribe');
  });

  test('a data frame decodes to its topic and {type, data, ts}', () {
    final decoded = protocol.decode({
      'topic': 'kline.60.BTCUSDT',
      'type': 'snapshot',
      'ts': 1,
      'data': [1, 2],
    });

    expect(decoded?.stream, 'kline.60.BTCUSDT');
    expect(decoded?.data, {
      'type': 'snapshot',
      'data': [1, 2],
      'ts': 1,
    });
  });

  test('acknowledgements and pongs are not data', () {
    expect(protocol.decode({'success': true, 'op': 'subscribe'}), isNull);
    expect(protocol.decode({'op': 'pong'}), isNull);
    expect(protocol.decode({'topic': 'x'}), isNull);
  });

  test('the client pings every 20 s', () {
    expect(jsonDecode(protocol.ping), {'op': 'ping'});
    expect(protocol.pingInterval, const Duration(seconds: 20));
  });
}
