import 'package:chart/chart.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_backtest/features_backtest.dart';
import 'package:features_shared/features_shared.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart' hide Interval;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Candle _c(int i) => Candle(
  openTime: DateTime.utc(2026, 9, 9, 12).add(Duration(hours: i)),
  open: Decimal.fromInt(100 + i % 7),
  high: Decimal.fromInt(101 + i % 7),
  low: Decimal.fromInt(99 + i % 7),
  close: Decimal.fromInt(100 + i % 7),
  volume: Decimal.fromInt(10 + i % 7),
);

Future<FakeMarketDataSource> _pumpScreen(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(800, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = FakeMarketDataSource(
    history: [for (var i = 0; i < 60; i++) _c(i)],
  );
  final btc = source.instrumentFor(defaultAssets.first, 'USDT');
  await tester.pumpWidget(
    testApp(
      overrides: fakeOverrides(source: source),
      home: BacktestScreen(instrument: btc, localTime: false),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
  return source;
}

void main() {
  testWidgets('loaded candles run a grid with results and trade markers', (
    tester,
  ) async {
    await _pumpScreen(tester);

    final locale = tester.element(find.byType(BacktestScreen)).localeTag;
    expect(
      find.text(
        '60 candles, '
        '${MoneyFormat.date(_c(0).openTime, locale: locale)} '
        '${MoneyFormat.time(_c(0).openTime, locale: locale)} – '
        '${MoneyFormat.date(_c(59).openTime, locale: locale)} '
        '${MoneyFormat.time(_c(59).openTime, locale: locale)}',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('bt_setup_a')), findsOneWidget);
    expect(find.byKey(const Key('bt_a_result')), findsNothing);

    await _run(tester, 'a');

    expect(find.byKey(const Key('bt_a_result')), findsOneWidget);
    expect(find.byKey(const Key('bt_net_profit')), findsOneWidget);
    final chart = tester.widget<CandleChart>(find.byType(CandleChart));
    expect(chart.markers, isNotEmpty);
  });

  testWidgets('invalid investment shows a validation error and no result', (
    tester,
  ) async {
    await _pumpScreen(tester);
    final l10n = tester.element(find.byType(BacktestScreen)).l10n;

    await tester.enterText(find.byKey(const Key('bt_a_investment')), 'abc');
    await tester.pump();
    await tester.tap(find.byKey(const Key('bt_a_run')));
    await tester.pump();

    expect(find.text(l10n.invalidNumber), findsOneWidget);
    expect(find.byKey(const Key('bt_a_result')), findsNothing);
    expect(find.byType(CandleChart), findsNothing);
  });

  testWidgets('comparison starts with DCA and runs the second setup', (
    tester,
  ) async {
    await _pumpScreen(tester);
    expect(find.byKey(const Key('bt_setup_b')), findsNothing);

    await tester.tap(find.byKey(const Key('bt_compare')));
    await tester.pump();

    final setupB = find.byKey(const Key('bt_setup_b'));
    expect(setupB, findsOneWidget);
    final kind = tester.widget<SegmentedButton<BotKind>>(
      find.descendant(of: setupB, matching: find.byKey(const Key('bt_b_kind'))),
    );
    expect(kind.selected, {BotKind.dca});
    expect(find.byKey(const Key('bt_b_result')), findsNothing);

    await _run(tester, 'b');

    expect(find.byKey(const Key('bt_b_result')), findsOneWidget);
  });

  testWidgets(
    'live close preserves edited investment and the next run uses it',
    (tester) async {
      final source = await _pumpScreen(tester);
      await tester.enterText(find.byKey(const Key('bt_a_investment')), '2500');
      await tester.pump();
      source.emitCandle(
        source.instrumentFor(defaultAssets.first, 'USDT'),
        _c(59).copyWith(close: Decimal.fromInt(120)),
      );
      await tester.pump();
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('bt_a_investment')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.text, '2500');
      await _run(tester, 'a');
      expect(_state(tester).resultA!.result.capital, Decimal.fromInt(2500));
    },
  );

  testWidgets('editing a field dims the result until rerun', (tester) async {
    await _pumpScreen(tester);
    await _run(tester, 'a');
    final l10n = tester.element(find.byType(BacktestScreen)).l10n;
    expect(find.text(l10n.backtestStale), findsNothing);
    await tester.enterText(find.byKey(const Key('bt_a_investment')), '2500');
    await tester.pump();
    expect(find.text(l10n.backtestStale), findsOneWidget);
    expect(
      tester
          .widget<Opacity>(find.byKey(const Key('bt_a_result_opacity')))
          .opacity,
      lessThan(1),
    );
    await _run(tester, 'a');
    expect(find.text(l10n.backtestStale), findsNothing);
    expect(
      tester
          .widget<Opacity>(find.byKey(const Key('bt_a_result_opacity')))
          .opacity,
      1,
    );
    expect(_state(tester).resultA!.result.capital, Decimal.fromInt(2500));
  });

  testWidgets('a same-length live candle replacement marks results stale', (
    tester,
  ) async {
    final source = await _pumpScreen(tester);
    await _run(tester, 'a');
    source.emitCandle(
      source.instrumentFor(defaultAssets.first, 'USDT'),
      _c(59).copyWith(close: Decimal.fromInt(120)),
    );
    await tester.pump();
    final l10n = tester.element(find.byType(BacktestScreen)).l10n;
    expect(find.text(l10n.backtestStale), findsOneWidget);
    await _run(tester, 'a');
    expect(find.text(l10n.backtestStale), findsNothing);
  });

  testWidgets('DCA fee of 100 shows invalidNumber without running', (
    tester,
  ) async {
    await _pumpScreen(tester);
    final l10n = tester.element(find.byType(BacktestScreen)).l10n;
    await tester.tap(find.text(l10n.backtestDca));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('bt_a_fee')), '100');
    await tester.pump();
    await tester.tap(find.byKey(const Key('bt_a_run')));
    await tester.pump();
    expect(find.text(l10n.invalidNumber), findsOneWidget);
    expect(_state(tester).resultA, isNull);
    expect(_state(tester).runningA, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Run shows progress and disables repeated taps', (tester) async {
    await _pumpScreen(tester);
    await tester.tap(find.byKey(const Key('bt_a_run')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('bt_a_run')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('bt_a_run'))).onPressed,
      isNull,
    );
    await _finishRun(tester, 'a');
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('bt_a_run'))).onPressed,
      isNotNull,
    );
  });

  testWidgets('comparison result survives removing and recreating its card', (
    tester,
  ) async {
    await _pumpScreen(tester);
    await tester.tap(find.byKey(const Key('bt_compare')));
    await tester.pump();
    await _run(tester, 'b');
    final result = _state(tester).resultB;
    await tester.ensureVisible(find.byKey(const Key('bt_compare')));
    await tester.tap(find.byKey(const Key('bt_compare')));
    await tester.pump();
    expect(find.byKey(const Key('bt_setup_b')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('bt_compare')));
    await tester.tap(find.byKey(const Key('bt_compare')));
    await tester.pump();
    expect(_state(tester).resultB, same(result));
    expect(find.byKey(const Key('bt_b_result')), findsOneWidget);
  });

  testWidgets('explains the backtest limitations', (tester) async {
    await _pumpScreen(tester);
    final l10n = tester.element(find.byType(BacktestScreen)).l10n;

    final limits = find.byKey(const Key('bt_limits'));
    expect(limits, findsOneWidget);
    expect(tester.widget<Text>(limits).data, l10n.backtestLimits);
  });
}

BacktestSetupsState _state(WidgetTester tester) {
  final element = tester.element(find.byType(BacktestScreen));
  final screen = element.widget as BacktestScreen;
  return ProviderScope.containerOf(element)
      .read(backtestSetupsProvider(screen.instrument.symbol));
}

Future<void> _run(WidgetTester tester, String prefix) async {
  await tester.ensureVisible(find.byKey(Key('bt_${prefix}_run')));
  await tester.tap(find.byKey(Key('bt_${prefix}_run')));
  await tester.pump();
  await _finishRun(tester, prefix);
}

Future<void> _finishRun(WidgetTester tester, String prefix) async {
  for (var i = 0; i < 1000; i++) {
    final state = _state(tester);
    if (!(prefix == 'a' ? state.runningA : state.runningB)) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    // Isolate completion resumes in the test's fake async zone.
    await tester.pump();
  }
  fail('Backtest did not finish');
}
