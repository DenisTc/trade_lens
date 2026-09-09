@Tags(['golden'])
library;

import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_markets/features_markets.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart' hide Interval;
import 'package:flutter_test/flutter_test.dart';

/// Pair screen in light and dark theme with deterministic data. Regenerate
/// with `fvm flutter test --update-goldens --tags golden`.
void main() {
  Candle candle(int i) => Candle(
    openTime: DateTime.utc(2026, 9, 9).add(Duration(hours: i)),
    open: Decimal.parse('100'),
    high: Decimal.parse('${101 + i % 3}'),
    low: Decimal.parse('${98 - i % 2}'),
    close: Decimal.parse(i.isEven ? '100.8' : '99.4'),
    volume: Decimal.fromInt(20 + (i * 7) % 30),
  );

  for (final brightness in Brightness.values) {
    testWidgets('pair screen · ${brightness.name}', (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final source = FakeMarketDataSource(
        history: [for (var i = 0; i < 60; i++) candle(i)],
      );
      final btc = source.instrumentFor(defaultAssets.first, 'USDT');
      await tester.pumpWidget(
        testApp(
          overrides: fakeOverrides(source: source),
          brightness: brightness,
          home: PairScreen(instrument: btc, localTime: false),
        ),
      );
      await tester.pump();
      await tester.pump();
      source
        ..emit(btc, '100.80', change: '0.80')
        ..emitBook(
          btc,
          OrderBookSnapshot(
            instrument: btc,
            bids: [
              for (var i = 0; i < 5; i++)
                OrderBookLevel(
                  price: Decimal.parse('100.${70 - i * 5}'),
                  qty: Decimal.parse('${1 + i * 0.5}'),
                ),
            ],
            asks: [
              for (var i = 0; i < 5; i++)
                OrderBookLevel(
                  price: Decimal.parse('100.${85 + i * 5}'),
                  qty: Decimal.parse('${0.5 + i * 0.25}'),
                ),
            ],
            at: DateTime.utc(2026),
          ),
        );
      for (var i = 0; i < 3; i++) {
        source.emitTrade(
          btc,
          Trade(
            instrument: btc,
            id: '$i',
            price: Decimal.parse('100.8'),
            qty: Decimal.parse('0.0${i + 1}'),
            at: DateTime.utc(2026, 9, 9, 12, 0, i),
            isBuyerMaker: i.isOdd,
          ),
        );
      }
      await tester.pump();

      await expectLater(
        find.byType(PairScreen),
        matchesGoldenFile('goldens/pair_screen_${brightness.name}.png'),
      );
    });
  }
}
