import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelens/app.dart';
import 'package:tradelens/router.dart';

void main() {
  testWidgets('starts on the markets screen with the app name', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TradeLensApp()));
    await tester.pumpAndSettle();

    expect(find.text('TradeLens'), findsOneWidget);
  });

  testWidgets('/p/:symbol opens the pair screen', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TradeLensApp(),
      ),
    );
    await tester.pumpAndSettle();

    container.read(routerProvider).go(AppRoutes.pairPath('ETHUSDT'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'ETHUSDT'), findsOneWidget);
  });

  testWidgets('markets placeholder navigates to BTCUSDT', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TradeLensApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('BTC/USDT'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'BTCUSDT'), findsOneWidget);
  });
}
