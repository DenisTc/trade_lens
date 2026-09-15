import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_backtest/features_backtest.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Candle _c(int i) => Candle(
  openTime: DateTime.utc(2026).add(Duration(hours: i)),
  open: Decimal.fromInt(100),
  high: Decimal.fromInt(101),
  low: Decimal.fromInt(99),
  close: Decimal.fromInt(100),
  volume: Decimal.one,
);

void main() {
  for (final second in [false, true]) {
    for (final asynchronous in [false, true]) {
      test(
        'captures ${asynchronous ? 'async' : 'sync'} runner errors for ${second ? 'B' : 'A'}',
        () async {
          final provider = backtestSetupsProvider('BTCUSDT');
          final container = ProviderContainer.test(
            overrides: [
              provider.overrideWith(
                () => BacktestSetups(
                  runner: (_, _) {
                    if (asynchronous) {
                      return Future.error(StateError('engine failed'));
                    }
                    throw StateError('engine failed');
                  },
                ),
              ),
            ],
          )..listen(provider, (_, _) {});
          final notifier = container.read(provider.notifier)
            ..seedIfEmpty(Decimal.fromInt(100));

          expect(await notifier.run([_c(0)], second: second), isNull);
          final state = container.read(provider);
          final result = second ? state.resultB : state.resultA;
          expect(result, isA<BacktestRunFailure>());
          expect(
            (result! as BacktestRunFailure).reason,
            'Bad state: engine failed',
          );
          expect(second ? state.resultA : state.resultB, isNull);
          expect(state.runningA, isFalse);
          expect(state.runningB, isFalse);
        },
      );
    }
  }

  test('seeding again preserves edits, comparison and both results', () async {
    final provider = backtestSetupsProvider('BTCUSDT');
    final container = ProviderContainer.test()..listen(provider, (_, _) {});
    final notifier = container.read(provider.notifier)
      ..seedIfEmpty(Decimal.fromInt(100))
      ..updateA(container.read(provider).a.with_('investment', '2500'))
      ..toggleCompare();
    final candles = [_c(0), _c(1)];
    await notifier.run(candles);
    await notifier.run(candles, second: true);
    notifier.seedIfEmpty(Decimal.fromInt(200));
    final state = container.read(provider);
    expect(state.a['investment'], '2500');
    expect(state.a['lower'], '90');
    expect(state.b['upper'], '110');
    expect(state.compare, isTrue);
    expect(
      (state.resultA! as BacktestRun).result.capital,
      Decimal.fromInt(2500),
    );
    expect(
      (state.resultB! as BacktestRun).result.capital,
      Decimal.fromInt(600),
    );
    expect((state.resultA! as BacktestRun).isStale(state.a, candles), isFalse);
    expect((state.resultB! as BacktestRun).isStale(state.b, candles), isFalse);
  });

  test(
    'run snapshots inputs before awaiting and ignores duplicate runs',
    () async {
      final provider = backtestSetupsProvider('BTCUSDT');
      final container = ProviderContainer.test()..listen(provider, (_, _) {});
      final notifier = container.read(provider.notifier)
        ..seedIfEmpty(Decimal.fromInt(100));
      final candles = [_c(0), _c(1)];
      final first = notifier.run(candles);
      expect(container.read(provider).runningA, isTrue);
      notifier.updateA(container.read(provider).a.with_('investment', '2500'));
      await notifier.run(candles);
      expect(container.read(provider).runningA, isTrue);
      await first;
      final state = container.read(provider);
      expect(state.runningA, isFalse);
      expect(
        (state.resultA! as BacktestRun).result.capital,
        Decimal.fromInt(1000),
      );
      expect((state.resultA! as BacktestRun).isStale(state.a, candles), isTrue);
      await notifier.run(candles);
      expect(
        (container.read(provider).resultA! as BacktestRun).result.capital,
        Decimal.fromInt(2500),
      );
      expect(
        (container.read(provider).resultA! as BacktestRun).isStale(
          state.a,
          candles,
        ),
        isFalse,
      );
    },
  );

  test('snapshot detects candle identity, length and kind changes', () async {
    final provider = backtestSetupsProvider('BTCUSDT');
    final container = ProviderContainer.test()..listen(provider, (_, _) {});
    final notifier = container.read(provider.notifier)
      ..seedIfEmpty(Decimal.fromInt(100));
    final candles = [_c(0), _c(1)];
    await notifier.run(candles);
    final state = container.read(provider);
    final run = state.resultA! as BacktestRun;
    expect(run.isStale(state.a, [...candles]), isTrue);
    expect(run.isStale(state.a.ofKind(BotKind.dca), candles), isTrue);
    // Equivalent values, even in a newly constructed setup, are not stale.
    expect(run.isStale(state.a.with_('investment', '1000'), candles), isFalse);
    candles.add(_c(2));
    expect(run.isStale(state.a, candles), isTrue);
    expect(run.candles, hasLength(2));
  });

  test('run uses only the newest 5000 candles', () async {
    final candles = [for (var i = 0; i < 5003; i++) _c(i)];
    final params = BacktestSetup.around(Decimal.fromInt(100))
        .parse()
        .valueOrNull!;
    final result = await runSetup(candles, params);
    // One initial-capital point, then one point per candle.
    expect(result.equity, hasLength(5001));
    expect(result.equity.first.at, DateTime.utc(2026, 1, 1, 3));
    expect(
      result.equity.last.at,
      DateTime.utc(2026).add(const Duration(hours: 5002)),
    );
  });

  test('DCA fee 100 is rejected before starting the engine', () async {
    final provider = backtestSetupsProvider('BTCUSDT');
    final container = ProviderContainer.test()..listen(provider, (_, _) {});
    final notifier = container.read(provider.notifier)
      ..seedIfEmpty(Decimal.fromInt(100))
      ..updateB(container.read(provider).b.with_('fee', '100'));
    expect(await notifier.run([_c(0)], second: true), 'fee');
    expect(container.read(provider).runningB, isFalse);
    expect(container.read(provider).resultB, isNull);
  });

  test(
    'leaving the screen during a run does not update disposed state',
    () async {
      final provider = backtestSetupsProvider('BTCUSDT');
      final container = ProviderContainer()..listen(provider, (_, _) {});
      final notifier = container.read(provider.notifier)
        ..seedIfEmpty(Decimal.fromInt(100));
      final run = notifier.run([_c(0)]);
      container.dispose();
      expect(await run, isNull);
    },
  );
}
