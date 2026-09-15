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
      ('levels', '201'),
      ('levels', '2.5'),
      ('investment', '0'),
      ('investment', '-1'),
      ('fee', '-0.1'),
      ('fee', '100'),
      ('fee', '101'),
    ]) {
      test('$field = $value names the invalid field', () {
        final setup = BacktestSetup.around(Decimal.fromInt(100))
            .with_(field, value);

        expect(setup.parse(), Err<Object, String>(field));
      });
    }
  });

  for (final (price, lower, upper) in [
    ('0.00000004', '0.000000036', '0.000000044'),
    ('0.04', '0.036', '0.044'),
    ('68123.45', '61310', '74940'),
    ('0', '0', '1'),
  ]) {
    test('around $price keeps distinct bounds at the price precision', () {
      final setup = BacktestSetup.around(Decimal.parse(price));
      expect(setup['lower'], lower);
      expect(setup['upper'], upper);
      expect(setup.parse().valueOrNull, isA<GridParams>());
    });
  }

  group('decimal separators', () {
    for (final (input, expected) in [
      ('1,5', '1.5'),
      ('0,1', '0.1'),
      ('1,25', '1.25'),
      ('1.000', '1'),
      ('1.5', '1.5'),
      ('1000', '1000'),
    ]) {
      test('accepts $input', () {
        final parsed = BacktestSetup.around(Decimal.fromInt(100))
            .with_('investment', input)
            .parse();
        expect(
          (parsed.valueOrNull! as GridParams).investment,
          Decimal.parse(expected),
        );
      });
    }
    for (final input in [
      '1,000',
      '1,',
      '1,2345',
      '1,5e2',
      '1,000.5',
      '1.000,5',
      '1,2,3',
      '1.2.3',
      '1 000',
      ' 1000 ',
      '1\u00a0000',
    ]) {
      test('rejects ambiguous or grouped $input', () {
        expect(
          BacktestSetup.around(Decimal.fromInt(100))
              .with_('investment', input)
              .parse(),
          const Err<Object, String>('investment'),
        );
      });
    }
  });

  group('DCA validation', () {
    for (final (field, value) in [
      ('fee', '100'),
      ('fee', '101'),
      ('fee', '-1'),
      ('takeProfit', '0'),
      ('takeProfit', '-1'),
      ('takeProfit', '1000.01'),
      ('step', '0'),
      ('step', '-1'),
      ('step', '100.01'),
      ('safetyOrders', '-1'),
      ('safetyOrders', '51'),
      ('safetyOrders', '1.5'),
      ('base', '0'),
      ('base', '-1'),
    ]) {
      test('$field = $value names the invalid field', () {
        expect(
          BacktestSetup.around(
            Decimal.fromInt(100),
            kind: BotKind.dca,
          ).with_(field, value).parse(),
          Err<Object, String>(field),
        );
      });
    }
    for (final (field, value) in [
      ('fee', '0'),
      ('fee', '99.99'),
      ('takeProfit', '1000'),
      ('step', '100'),
      ('safetyOrders', '0'),
      ('safetyOrders', '50'),
    ]) {
      test('accepts boundary $field = $value', () {
        expect(
          BacktestSetup.around(
            Decimal.fromInt(100),
            kind: BotKind.dca,
          ).with_(field, value).parse().valueOrNull,
          isA<DcaParams>(),
        );
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
