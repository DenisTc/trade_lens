import 'dart:convert';

import 'package:backtest/backtest.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  BacktestResult result({bool zero = false}) => BacktestResult(
    capital: zero ? Decimal.zero : Decimal.fromInt(1000),
    trades: [
      BacktestTrade(
        at: DateTime.utc(2026),
        side: TradeSide.sell,
        price: Decimal.fromInt(110),
        qty: Decimal.one,
        fee: Decimal.one,
        realizedPnl: Decimal.fromInt(9),
      ),
    ],
    equity: const [],
    finalEquity: Decimal.fromInt(1050),
    fees: Decimal.parse('2.50'),
    maxDrawdown: Decimal.fromInt(20),
    baseHeld: Decimal.parse('0.125'),
    quoteHeld: Decimal.fromInt(900),
  );
  BacktestMetrics metrics(BacktestResult result, Map<String, String> params) =>
      BacktestMetrics.fromResult(
        result,
        kind: 'grid',
        params: params,
        symbol: 'BTCUSDT',
        intervalCode: '1h',
        candleCount: 60,
        from: DateTime.utc(2026, 9, 9),
        to: DateTime.utc(2026, 9, 11),
      );

  test('captures computed figures and exact typed parameters as JSON', () {
    final params = {'investment': '1000.00', 'fee': '0,1'};
    final value = metrics(result(), params);
    params['fee'] = '99';
    expect(value.params['fee'], '0,1');
    expect(() => value.params['fee'] = '1', throwsUnsupportedError);
    expect(jsonDecode(jsonEncode(value.toJson())), {
      'kind': 'grid',
      'params': {'investment': '1000.00', 'fee': '0,1'},
      'symbol': 'BTCUSDT',
      'intervalCode': '1h',
      'candleCount': 60,
      'from': '2026-09-09T00:00:00.000Z',
      'to': '2026-09-11T00:00:00.000Z',
      'capital': '1000',
      'netProfit': '50',
      'netProfitPct': '5',
      'tradeCount': 1,
      'closedRoundTrips': 1,
      'winningRoundTrips': 1,
      'maxDrawdown': '20',
      'maxDrawdownPct': '2',
      'fees': '2.5',
      'finalEquity': '1050',
      'baseHeld': '0.125',
    });
  });
  test('undefined percentages stay null for zero capital', () {
    final json = metrics(result(zero: true), {}).toJson();
    expect(json['netProfitPct'], isNull);
    expect(json['maxDrawdownPct'], isNull);
  });
}
