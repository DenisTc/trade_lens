import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_markets/features_markets.dart';
import 'package:features_shared/features_shared.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeMarketDataSource source;
  final opened = <Instrument>[];

  Widget app({Future<MarketDataSource> Function()? sourceFactory}) =>
      ProviderScope(
        retry: noRetry,
        overrides: fakeOverrides(source: source, sourceFactory: sourceFactory),
        child: MaterialApp(home: MarketsScreen(onOpenPair: opened.add)),
      );

  setUp(() {
    source = FakeMarketDataSource();
    opened.clear();
  });

  testWidgets('shows loading, then the catalog, then live prices', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester.pump();
    expect(find.text('BTC/USDT'), findsOneWidget);
    expect(find.text('Bitcoin'), findsOneWidget);

    final btc = source.instrumentFor(defaultAssets.first, 'USDT');
    source.emit(btc, '78339.52', change: '-1.939');
    await tester.pump();
    expect(find.text('78 339.52'), findsOneWidget);
    expect(find.text('-1.94%'), findsOneWidget);
  });

  testWidgets('search filters by symbol and by name', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();

    await tester.enterText(find.byKey(const Key('markets_search')), 'eth');
    await tester.pump();
    expect(find.text('ETH/USDT'), findsOneWidget);
    expect(find.text('BTC/USDT'), findsNothing);

    await tester.enterText(find.byKey(const Key('markets_search')), 'cardano');
    await tester.pump();
    expect(find.text('ADA/USDT'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('markets_search')), 'zzz');
    await tester.pump();
    expect(find.text('Nothing matches'), findsOneWidget);
  });

  testWidgets('tapping a row opens the pair', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.tap(find.text('BTC/USDT'));
    expect(opened.single.symbol, 'BTCUSDT');
  });

  testWidgets('source failure shows the error view with retry', (tester) async {
    await tester.pumpWidget(
      app(
        sourceFactory: () async =>
            throw const MarketError.network(sourceId: 'x', reason: 'offline'),
      ),
    );
    await tester.pump();
    await tester.pump(); // the failed future settles one microtask later
    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('attribution badge shows the source text', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.text('Data: Fake'), findsOneWidget);
  });

  test('filterInstruments is case-insensitive', () {
    final all = source.instruments(defaultAssets, 'USDT');
    expect(filterInstruments(all, 'BTC').single.symbol, 'BTCUSDT');
    expect(filterInstruments(all, ' Solana ').single.symbol, 'SOLUSDT');
    expect(filterInstruments(all, ''), all);
  });

  test('formatPrice groups thousands and scales fraction digits', () {
    expect(formatPrice(Decimal.parse('78339.52000000')), '78 339.52');
    expect(formatPrice(Decimal.parse('1.5')), '1.5000');
    expect(formatPrice(Decimal.parse('0.000123456')), '0.000123');
    expect(formatChangePct(Decimal.parse('1.939')), '+1.94%');
    expect(formatChangePct(Decimal.parse('-0.3')), '-0.30%');
    expect(formatChangePct(null), isNull);
  });
}
