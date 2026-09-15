import 'dart:isolate';

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
    final ten = price * Decimal.parse('0.1');
    return BacktestSetup(
      kind: kind,
      fields: {
        'lower': price <= Decimal.zero ? '0' : _priceText(price - ten, price),
        'upper': price <= Decimal.zero ? '1' : _priceText(price + ten, price),
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
      final v = parseBacktestNumber(this[f]);
      return v == null || v < Decimal.zero ? null : v;
    }

    int? count(String f) {
      final v = int.tryParse(this[f].trim());
      return v == null || v < 0 ? null : v;
    }

    final fee = num('fee');
    if (fee == null || fee >= Decimal.fromInt(100)) return const Err('fee');
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
        if (step == null ||
            step == Decimal.zero ||
            step > Decimal.fromInt(100)) {
          return const Err('step');
        }
        if (tp == null || tp == Decimal.zero || tp > Decimal.fromInt(1000)) {
          return const Err('takeProfit');
        }
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

/// A single comma with one or two fractional digits is a decimal separator.
/// Other comma forms are ambiguous or grouped and are rejected.
Decimal? parseBacktestNumber(String text) {
  final commas = ','.allMatches(text).length;
  final dots = '.'.allMatches(text).length;
  if (commas + dots > 1 || RegExp(r'\s').hasMatch(text)) return null;
  if (commas == 1 && !RegExp(r'^[+-]?[0-9]*,[0-9]{1,2}$').hasMatch(text)) {
    return null;
  }
  return Decimal.tryParse(commas == 1 ? text.replaceFirst(',', '.') : text);
}

/// Normalizing the reference price into [0.1, 1) gives the decimal exponent
/// whose exponent + 4 places retain four significant digits of that price.
String _priceText(Decimal bound, Decimal price) {
  var normalized = price;
  var exponent = 0;
  final tenth = Decimal.parse('0.1');
  final ten = Decimal.fromInt(10);
  while (normalized < tenth) {
    normalized *= ten;
    exponent++;
  }
  while (normalized >= Decimal.one) {
    normalized *= tenth;
    exponent--;
  }
  return bound.round(scale: exponent + 4).toString();
}

/// Runs [params] over the newest 5000 candles, oldest first, off the UI isolate.
Future<BacktestResult> runSetup(List<Candle> candles, Object params) {
  final input = _latestCandles(candles);
  return Isolate.run(
    () => switch (params) {
      GridParams() => runGrid(input, params),
      DcaParams() => runDca(input, params),
      _ => throw ArgumentError.value(params, 'params'),
    },
  );
}

List<Candle> _latestCandles(List<Candle> candles) => List.unmodifiable(
  candles.skip(candles.length > 5000 ? candles.length - 5000 : 0),
);

typedef BacktestRunner = Future<BacktestResult> Function(
  List<Candle> candles,
  Object params,
);

@immutable
sealed class BacktestRunOutcome {
  const BacktestRunOutcome();
}

final class BacktestRunFailure extends BacktestRunOutcome {
  const BacktestRunFailure(this.reason);

  final String reason;
}

/// The parameters and candle window belonging to a successful run.
@immutable
final class BacktestRun extends BacktestRunOutcome {
  BacktestRun({
    required this.result,
    required BacktestSetup setup,
    required this.sourceCandles,
    required this.candles,
    required this.sourceLength,
    required this.interval,
  }) : setup = BacktestSetup(
         kind: setup.kind,
         fields: Map.unmodifiable(setup.fields),
       );

  final BacktestResult result;
  final Interval? interval;
  final BacktestSetup setup;
  final List<Candle> sourceCandles;
  final int sourceLength;
  final List<Candle> candles;

  bool isStale(BacktestSetup current, List<Candle> candles) =>
      !identical(sourceCandles, candles) ||
      sourceLength != candles.length ||
      setup.kind != current.kind ||
      setup.fields.length != current.fields.length ||
      setup.fields.entries.any((entry) => current[entry.key] != entry.value);
}

@immutable
final class BacktestSetupsState {
  const BacktestSetupsState({
    this.a = const BacktestSetup(kind: BotKind.grid, fields: {}),
    this.b = const BacktestSetup(kind: BotKind.dca, fields: {}),
    this.seeded = false,
    this.compare = false,
    this.resultA,
    this.resultB,
    this.runningA = false,
    this.runningB = false,
  });

  final BacktestSetup a;
  final BacktestSetup b;
  final bool seeded;
  final bool compare;
  final BacktestRunOutcome? resultA;
  final BacktestRunOutcome? resultB;
  final bool runningA;
  final bool runningB;

  BacktestSetupsState copyWith({
    BacktestSetup? a,
    BacktestSetup? b,
    bool? seeded,
    bool? compare,
    BacktestRunOutcome? resultA,
    BacktestRunOutcome? resultB,
    bool? runningA,
    bool? runningB,
  }) => BacktestSetupsState(
    a: a ?? this.a,
    b: b ?? this.b,
    seeded: seeded ?? this.seeded,
    compare: compare ?? this.compare,
    resultA: resultA ?? this.resultA,
    resultB: resultB ?? this.resultB,
    runningA: runningA ?? this.runningA,
    runningB: runningB ?? this.runningB,
  );
}

/// Both cards share this symbol-keyed state. The screen holds its subscription
/// even when a card is scrolled away or candles are loading.
@riverpod
class BacktestSetups extends _$BacktestSetups {
  BacktestSetups({this.runner = runSetup});

  final BacktestRunner runner;

  @override
  BacktestSetupsState build(String symbol) => const BacktestSetupsState();

  void seedIfEmpty(Decimal price) {
    if (state.seeded) return;
    state = state.copyWith(
      a: BacktestSetup.around(price),
      b: BacktestSetup.around(price, kind: BotKind.dca),
      seeded: true,
    );
  }

  void updateA(BacktestSetup a) => state = state.copyWith(a: a);
  void updateB(BacktestSetup b) => state = state.copyWith(b: b);
  void toggleCompare() => state = state.copyWith(compare: !state.compare);

  Future<String?> run(
    List<Candle> candles, {
    bool second = false,
    Interval? interval,
  }) async {
    if (second ? state.runningB : state.runningA) return null;
    final current = second ? state.b : state.a;
    final setup = BacktestSetup(
      kind: current.kind,
      fields: Map.unmodifiable(current.fields),
    );
    final parsed = setup.parse();
    if (parsed case Err(:final error)) return error;
    final params = parsed.valueOrNull!;
    // Capture everything before the await: edits and ticks during a run must
    // make the completed result stale as well.
    final input = _latestCandles(candles);
    final sourceLength = candles.length;
    _setRun(second, running: true);
    try {
      final result = await runner(input, params);
      if (!ref.mounted) return null;
      final snapshot = BacktestRun(
        result: result,
        interval: interval,
        setup: setup,
        sourceCandles: candles,
        candles: input,
        sourceLength: sourceLength,
      );
      _setRun(second, running: false, result: snapshot);
    } on Object catch (error) {
      if (ref.mounted) {
        _setRun(
          second,
          running: false,
          result: BacktestRunFailure(error.toString()),
        );
      }
    } finally {
      if (ref.mounted) _setRun(second, running: false);
    }
    return null;
  }

  void _setRun(
    bool second, {
    required bool running,
    BacktestRunOutcome? result,
  }) {
    state = second
        ? state.copyWith(runningB: running, resultB: result)
        : state.copyWith(runningA: running, resultA: result);
  }
}
