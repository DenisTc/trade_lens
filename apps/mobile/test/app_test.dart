import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelens/app.dart';
import 'package:tradelens/router.dart';

void main() {
  late FakeMarketDataSource source;

  setUp(() => source = FakeMarketDataSource());

  // `Override` is not exported by flutter_riverpod's public library, so the
  // scope is built here instead of typing a list of overrides.
  Widget scoped() => ProviderScope(
    retry: noRetry,
    overrides: [marketDataSourceProvider.overrideWith((ref) async => source)],
    child: const TradeLensApp(),
  );

  testWidgets('starts on the markets list with the app name', (tester) async {
    await tester.pumpWidget(scoped());
    await tester.pump();

    expect(find.text('TradeLens'), findsOneWidget);
    expect(find.text('BTC/USDT'), findsOneWidget);
  });

  testWidgets('/p/:symbol opens the pair screen', (tester) async {
    final container = ProviderContainer(
      retry: noRetry,
      overrides: [marketDataSourceProvider.overrideWith((ref) async => source)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TradeLensApp(),
      ),
    );
    await tester.pump();

    container.read(routerProvider).go(AppRoutes.pairPath('ETHUSDT'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'ETHUSDT'), findsOneWidget);
  });

  testWidgets('tapping a pair navigates to it', (tester) async {
    await tester.pumpWidget(scoped());
    await tester.pump();

    await tester.tap(find.text('BTC/USDT'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'BTCUSDT'), findsOneWidget);
  });

  testWidgets('live price reaches the list', (tester) async {
    await tester.pumpWidget(scoped());
    await tester.pump();
    source.emit(source.instrumentFor(defaultAssets.first, 'USDT'), '50000');
    await tester.pump();
    expect(find.text('50 000.00'), findsOneWidget);
  });
}
