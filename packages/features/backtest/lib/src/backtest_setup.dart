import 'package:backtest/backtest.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'backtest_setup.g.dart';

enum BotKind { grid, dca }

/// One set of parameters, as the form holds them: strings, because the
/// user is typing, validated into engine parameters on demand.
@immutable
final class BacktestSetup {
  const BacktestSetup({required this.kind, required this.fields});

  /// Sensible starting values around [price]: a grid ±10 % with ten
  /// levels, a DCA with five safety orders two percent apart.
  factory BacktestSetup.around(Decimal price, {BotKind kind = BotKind.grid}) {
    final ten = (price * Decimal.parse('0.1')).round(scale: 2);
    return BacktestSetup(
      kind: kind,
      fields: {
        'lower': '${(price - ten).round(scale: 2)}',
        'upper': '${(price + ten).round(scale: 2)}',
        'levels': '10',
        'investment': '1000',
        'fee': '0.1',
        'base': '100',
        'safety': '100',
        'safetyOrders': '5',
        'step': '2',
        'takeProfit': '1.5',
      },
    );
  }

  final BotKind kind;
  final Map<String, String> fields;

  BacktestSetup with_(String field, String value) =>
      BacktestSetup(kind: kind, fields: {...fields, field: value});

  BacktestSetup ofKind(BotKind next) =>
      BacktestSetup(kind: next, fields: fields);

  String operator [](String field) => fields[field] ?? '';

  /// The engine parameters, or the name of the first field that cannot
  /// be read as a positive number (or a sensible count).
  Result<Object, String> parse() {
    Decimal? num(String f) {
      final v = Decimal.tryParse(this[f].trim().replaceAll(',', '.'));
      return v == null || v < Decimal.zero ? null : v;
    }

    int? count(String f) {
      final v = int.tryParse(this[f].trim());
      return v == null || v < 0 ? null : v;
    }

    final fee = num('fee');
    if (fee == null) return const Err('fee');
    final feeRate = (fee / Decimal.fromInt(100)).toDecimal(
      scaleOnInfinitePrecision: 8,
    );
    switch (kind) {
      case BotKind.grid:
        final lower = num('lower');
        final upper = num('upper');
        final levels = count('levels');
        final investment = num('investment');
        if (lower == null) return const Err('lower');
        if (upper == null || upper <= lower) return const Err('upper');
        if (levels == null || levels < 2 || levels > 200) {
          return const Err('levels');
        }
        if (investment == null || investment == Decimal.zero) {
          return const Err('investment');
        }
        return Ok(
          GridParams(
            lower: lower,
            upper: upper,
            levels: levels,
            investment: investment,
            feeRate: feeRate,
          ),
        );
      case BotKind.dca:
        final base = num('base');
        final safety = num('safety');
        final safetyOrders = count('safetyOrders');
        final step = num('step');
        final tp = num('takeProfit');
        if (base == null || base == Decimal.zero) return const Err('base');
        if (safety == null) return const Err('safety');
        if (safetyOrders == null || safetyOrders > 50) {
          return const Err('safetyOrders');
        }
        if (step == null || step == Decimal.zero) return const Err('step');
        if (tp == null || tp == Decimal.zero) return const Err('takeProfit');
        return Ok(
          DcaParams(
            baseOrder: base,
            safetyOrder: safety,
            safetyOrders: safetyOrders,
            stepPct: step,
            takeProfitPct: tp,
            feeRate: feeRate,
          ),
        );
    }
  }
}

/// Runs [params] over [candles], oldest first.
BacktestResult runSetup(List<Candle> candles, Object params) =>
    switch (params) {
      GridParams() => runGrid(candles, params),
      DcaParams() => runDca(candles, params),
      _ => throw ArgumentError.value(params, 'params'),
    };

/// The form's state for one pair: two sets, so that a second one can be
/// compared with the first, and whether the second is shown. Lives as
/// long as the screen; nothing is persisted.
@riverpod
class BacktestSetups extends _$BacktestSetups {
  @override
  ({BacktestSetup a, BacktestSetup b, bool compare}) build(
    String symbol,
    Decimal price,
  ) => (
    a: BacktestSetup.around(price),
    b: BacktestSetup.around(price, kind: BotKind.dca),
    compare: false,
  );

  void updateA(BacktestSetup a) =>
      state = (a: a, b: state.b, compare: state.compare);
  void updateB(BacktestSetup b) =>
      state = (a: state.a, b: b, compare: state.compare);
  void toggleCompare() =>
      state = (a: state.a, b: state.b, compare: !state.compare);
}
