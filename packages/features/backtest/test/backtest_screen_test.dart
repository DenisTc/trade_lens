import 'package:chart/chart.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_backtest/features_backtest.dart';
import 'package:features_shared/features_shared.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart' hide Interval;
import 'package:flutter_test/flutter_test.dart';

Candle _c(int i) => Candle(
  openTime: DateTime.utc(2026, 9, 9, 12).add(Duration(hours: i)),
  open: Decimal.fromInt(100 + i % 7),
  high: Decimal.fromInt(101 + i % 7),
  low: Decimal.fromInt(99 + i % 7),
  close: Decimal.fromInt(100 + i % 7),
  volume: Decimal.fromInt(10 + i % 7),
);

Future<void> _pumpScreen(WidgetTester tester) async {
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
}

void main() {
  testWidgets('loaded candles run a grid with results and trade markers', (
    tester,
  ) async {
    await _pumpScreen(tester);

    expect(find.textContaining('60 candles,'), findsOneWidget);
    expect(find.byKey(const Key('bt_setup_a')), findsOneWidget);
    expect(find.byKey(const Key('bt_a_result')), findsNothing);

    await tester.tap(find.byKey(const Key('bt_a_run')));
    await tester.pump();

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

    await tester.tap(find.byKey(const Key('bt_b_run')));
    await tester.pump();

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
