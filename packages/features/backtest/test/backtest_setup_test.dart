import 'package:backtest/backtest.dart';
import 'package:core/core.dart';
import 'package:features_backtest/features_backtest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('around seeds grid and DCA defaults around the supplied price', () {
    final setup = BacktestSetup.around(Decimal.fromInt(200));

    expect(setup.kind, BotKind.grid);
    expect(setup.fields, {
      'lower': '180',
      'upper': '220',
      'levels': '10',
      'investment': '1000',
      'fee': '0.1',
      'base': '100',
      'safety': '100',
      'safetyOrders': '5',
      'step': '2',
      'takeProfit': '1.5',
    });
    expect(
      BacktestSetup.around(Decimal.fromInt(200), kind: BotKind.dca).kind,
      BotKind.dca,
    );
  });

  group('parse rejects invalid grid fields', () {
    for (final (field, value) in [
      ('upper', '90'),
      ('upper', '89'),
      ('levels', '1'),
      ('investment', '0'),
      ('fee', '-0.1'),
    ]) {
      test('$field = $value names the invalid field', () {
        final setup = BacktestSetup.around(Decimal.fromInt(100))
            .with_(field, value);

        expect(setup.parse(), Err<Object, String>(field));
      });
    }
  });

  test('valid grid converts percentage fee to a fractional rate', () {
    final result = BacktestSetup.around(Decimal.fromInt(100)).parse();

    expect(result.valueOrNull, isA<GridParams>());
    final params = result.valueOrNull! as GridParams;
    expect(params.lower, Decimal.fromInt(90));
    expect(params.upper, Decimal.fromInt(110));
    expect(params.levels, 10);
    expect(params.investment, Decimal.fromInt(1000));
    expect(params.feeRate, Decimal.parse('0.001'));
  });

  test('valid DCA parses its order and percentage parameters', () {
    final result = BacktestSetup.around(
      Decimal.fromInt(100),
      kind: BotKind.dca,
    ).parse();

    expect(result.valueOrNull, isA<DcaParams>());
    final params = result.valueOrNull! as DcaParams;
    expect(params.baseOrder, Decimal.fromInt(100));
    expect(params.safetyOrder, Decimal.fromInt(100));
    expect(params.safetyOrders, 5);
    expect(params.stepPct, Decimal.fromInt(2));
    expect(params.takeProfitPct, Decimal.parse('1.5'));
    expect(params.feeRate, Decimal.parse('0.001'));
  });
}
