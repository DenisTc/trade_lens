import 'package:backtest/backtest.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('a rising candle visits its low first, a falling one its high', () {
    expect(candlePath(c(0, '100', '110', '90', '105')).map((p) => '$p'), [
      '100',
      '90',
      '110',
      '105',
    ]);
    expect(candlePath(c(0, '100', '110', '90', '95')).map((p) => '$p'), [
      '100',
      '110',
      '90',
      '95',
    ]);
  });

  test('drawdown is peak to trough, zero for a curve that only rises', () {
    expect(
      maxDrawdownOf([d('100'), d('120'), d('90'), d('130'), d('125')]),
      d('30'),
    );
    expect(maxDrawdownOf([d('1'), d('2'), d('3')]), d('0'));
    expect(maxDrawdownOf(const []), d('0'));
  });
}
