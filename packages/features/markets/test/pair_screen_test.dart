import 'package:chart/chart.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_markets/features_markets.dart';
import 'package:features_shared/features_shared.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart' hide Interval;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Candle _c(int i, {Duration step = const Duration(minutes: 1)}) => Candle(
  openTime: DateTime.utc(2026, 9, 9, 12).add(step * i),
  open: Decimal.parse('100'),
  high: Decimal.parse('101'),
  low: Decimal.parse('99'),
  close: Decimal.parse(i.isEven ? '100.5' : '99.5'),
  volume: Decimal.fromInt(10 + i % 7),
);

void main() {
  Widget app(FakeMarketDataSource source, Instrument instrument) =>
      ProviderScope(
        retry: noRetry,
        overrides: [
          marketDataSourceProvider.overrideWith((ref) async => source),
        ],
        child: MaterialApp(
          home: PairScreen(instrument: instrument, localTime: false),
        ),
      );

  testWidgets('full source: chart, interval selector, book and tape', (
    tester,
  ) async {
    // Tall surface so the book and tape sections are built, not lazily
    // skipped by the ListView.
    tester.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = FakeMarketDataSource(
      history: [for (var i = 0; i < 50; i++) _c(i)],
    );
    final btc = source.instrumentFor(defaultAssets.first, 'USDT');
    await tester.pumpWidget(app(source, btc));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('interval_selector')), findsOneWidget);
    expect(find.byKey(const Key('pair_chart')), findsOneWidget);
    expect(find.text('Order book'), findsOneWidget);
    expect(find.text('Trades'), findsOneWidget);

    source
      ..emit(btc, '100.25', change: '1.2')
      ..emitBook(
        btc,
        OrderBookSnapshot(
          instrument: btc,
          bids: [
            OrderBookLevel(
              price: Decimal.parse('100.2'),
              qty: Decimal.parse('1.5'),
            ),
          ],
          asks: [
            OrderBookLevel(
              price: Decimal.parse('100.3'),
              qty: Decimal.parse('0.5'),
            ),
          ],
          at: DateTime.utc(2026),
        ),
      )
      ..emitTrade(
        btc,
        Trade(
          instrument: btc,
          id: '1',
          price: Decimal.parse('100.25'),
          qty: Decimal.parse('0.1'),
          at: DateTime.utc(2026),
          isBuyerMaker: true,
        ),
      );
    await tester.pump();

    expect(find.byKey(const Key('pair_price')), findsOneWidget);
    expect(find.text('100.2500'), findsWidgets);
    expect(find.byKey(const Key('order_book_bids')), findsOneWidget);
    expect(find.text('0.1000'), findsOneWidget);
  });

  testWidgets('prices-only source hides selector, book and tape', (
    tester,
  ) async {
    final source = FakeMarketDataSource(
      capabilities: Capabilities.pricesOnly,
      history: [
        for (var i = 0; i < 20; i++) _c(i, step: const Duration(minutes: 30)),
      ],
    );
    final btc = source.instrumentFor(defaultAssets.first, 'USDT');
    await tester.pumpWidget(app(source, btc));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('interval_selector')), findsNothing);
    expect(find.text('Order book'), findsNothing);
    expect(find.text('Trades'), findsNothing);
    expect(find.byKey(const Key('prices_only_note')), findsOneWidget);
    expect(find.textContaining('30m · auto'), findsOneWidget);
    final chart = tester.widget<CandleChart>(
      find.byKey(const Key('pair_chart')),
    );
    expect(chart.showVolume, isFalse);
  });

  testWidgets('history failure shows an error with retry', (tester) async {
    final source = FakeMarketDataSource(
      klinesError: const MarketError.unavailable(
        sourceId: 'fake',
        reason: 'timeout',
      ),
    );
    final btc = source.instrumentFor(defaultAssets.first, 'USDT');
    await tester.pumpWidget(app(source, btc));
    await tester.pump();
    await tester.pump();
    expect(find.byType(ErrorView), findsOneWidget);
  });

  testWidgets('changing the interval reloads candles', (tester) async {
    final source = FakeMarketDataSource(history: [_c(0)]);
    final btc = source.instrumentFor(defaultAssets.first, 'USDT');
    await tester.pumpWidget(app(source, btc));
    await tester.pump();
    await tester.pump();
    expect(source.klineRequests.map((r) => r.$2), [Interval.h1]);

    await tester.tap(find.text('15m'));
    await tester.pump();
    await tester.pump();
    expect(source.klineRequests.map((r) => r.$2), [Interval.h1, Interval.m15]);
  });

  test('incrementalSeries reuses the previous series for tail updates', () {
    final first = [for (var i = 0; i < 5; i++) _c(i)];
    final series = incrementalSeries(null, null, first);
    expect(series.length, 5);

    final updated = [...first.take(4), _c(4)]; // live update of the last
    final next = incrementalSeries(first, series, updated);
    expect(next.length, 5);
    expect(identical(next, series), isFalse);

    final appended = [...updated, _c(5)];
    expect(incrementalSeries(updated, next, appended).length, 6);

    final rebuilt = incrementalSeries(appended, next, [_c(9)]);
    expect(rebuilt.length, 1, reason: 'shrunk list → full rebuild');
  });

  test('chartIntervalFor labels auto by observed granularity', () {
    expect(chartIntervalFor(Interval.h1, const []).label, '1h');
    final auto = chartIntervalFor(Interval.auto, [
      for (var i = 0; i < 5; i++) _c(i, step: const Duration(hours: 4)),
    ]);
    expect(auto.duration, const Duration(hours: 4));
    expect(auto.label, '4h · auto');
  });
}
