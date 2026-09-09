import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_portfolio/features_portfolio.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final btc = defaultAssets.first;

  Position position(String qty, String price) => Position(
    id: 'p1',
    asset: btc,
    quote: 'USDT',
    qty: Decimal.parse(qty),
    avgPrice: Decimal.parse(price),
    createdAt: DateTime.utc(2026, 9, 9),
  );

  Future<void> pumpTimes(WidgetTester tester, int n) async {
    for (var i = 0; i < n; i++) {
      await tester.pump();
    }
  }

  testWidgets('empty state and add flow', (tester) async {
    final source = FakeMarketDataSource();
    final repo = FakePortfolioRepository();
    await tester.pumpWidget(
      testApp(
        overrides: fakeOverrides(source: source, portfolio: repo),
        home: const PortfolioScreen(),
      ),
    );
    await pumpTimes(tester, 3);
    expect(find.byKey(const Key('portfolio_empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('add_position')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('position_qty')), '0,5');
    await tester.enterText(find.byKey(const Key('position_price')), '60000');
    await tester.tap(find.byKey(const Key('position_save')));
    await tester.pumpAndSettle();

    final stored = (await repo.positions()).single;
    expect(stored.qty, Decimal.parse('0.5'));
    expect(stored.avgPrice, Decimal.fromInt(60000));
    expect(find.text('BTC/USDT'), findsOneWidget);
  });

  testWidgets('live quote values the portfolio and shows Live', (tester) async {
    final source = FakeMarketDataSource();
    final repo = FakePortfolioRepository();
    await repo.upsert(position('0.5', '60000'));
    await tester.pumpWidget(
      testApp(
        overrides: fakeOverrides(source: source, portfolio: repo),
        home: const PortfolioScreen(),
      ),
    );
    await pumpTimes(tester, 4);
    source.emit(source.instrumentFor(btc, 'USDT'), '70000');
    await pumpTimes(tester, 4);

    expect(
      tester.widget<Text>(find.byKey(const Key('portfolio_total'))).data,
      '35,000.00',
    );
    expect(find.byKey(const Key('valuation_status')), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.textContaining('+16.67%'), findsNWidgets(2));
  });

  testWidgets('stored quote shows "As of" time', (tester) async {
    final source = FakeMarketDataSource();
    final repo = FakePortfolioRepository();
    await repo.upsert(position('1', '60000'));
    final store = FakeLastQuoteStore();
    await store.save(
      Quote(
        instrument: source.instrumentFor(btc, 'USDT'),
        price: Decimal.parse('65000'),
        change24hPct: null,
        at: DateTime.utc(2026, 9, 9, 12, 40),
      ),
    );
    await tester.pumpWidget(
      testApp(
        overrides: fakeOverrides(
          source: source,
          portfolio: repo,
          lastQuotes: store,
        ),
        home: const PortfolioScreen(),
      ),
    );
    await pumpTimes(tester, 5);
    expect(find.textContaining('As of'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('portfolio_total'))).data,
      '65,000.00',
    );
  });

  testWidgets('russian locale formats numbers and strings', (tester) async {
    final source = FakeMarketDataSource();
    final repo = FakePortfolioRepository();
    await repo.upsert(position('1', '1000'));
    await tester.pumpWidget(
      testApp(
        overrides: fakeOverrides(source: source, portfolio: repo),
        locale: const Locale('ru'),
        home: const PortfolioScreen(),
      ),
    );
    await pumpTimes(tester, 4);
    source.emit(source.instrumentFor(btc, 'USDT'), '2000');
    await pumpTimes(tester, 4);
    expect(find.text('Портфель'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('portfolio_total'))).data,
      '2\u00a0000,00',
    );
  });

  test('parseDecimal accepts comma and rejects non-positive', () {
    expect(parseDecimal('1,5'), Decimal.parse('1.5'));
    expect(parseDecimal(' 60 000 '), Decimal.fromInt(60000));
    expect(parseDecimal('0'), isNull);
    expect(parseDecimal('abc'), isNull);
  });
}
