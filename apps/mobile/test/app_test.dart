import 'package:domain/domain.dart';
import 'package:features_portfolio/features_portfolio.dart';
import 'package:features_shared/features_shared.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelens/app.dart';
import 'package:tradelens/router.dart';
import 'package:tradelens/screens/home_shell.dart';

void main() {
  late FakeMarketDataSource source;

  setUp(() => source = FakeMarketDataSource());

  // `Override` is not exported by flutter_riverpod's public library, so the
  // scope is built here instead of typing a list of overrides.
  Widget scoped() => ProviderScope(
    retry: noRetry,
    overrides: fakeOverrides(source: source),
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
      overrides: fakeOverrides(source: source),
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
    // No pumpAndSettle: the pair screen keeps a spinner while the fake
    // source stays silent.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.widgetWithText(AppBar, 'ETH/USDT'), findsOneWidget);
  });

  testWidgets('tapping a pair navigates to it', (tester) async {
    await tester.pumpWidget(scoped());
    await tester.pump();

    await tester.tap(find.text('BTC/USDT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.widgetWithText(AppBar, 'BTC/USDT'), findsOneWidget);
  });

  testWidgets('live price reaches the list', (tester) async {
    await tester.pumpWidget(scoped());
    await tester.pump();
    source.emit(source.instrumentFor(defaultAssets.first, 'USDT'), '50000');
    await tester.pump();
    expect(find.text('50,000.00'), findsOneWidget);
  });

  testWidgets('glass tabs switch branches; the theme setting picks the mode', (
    tester,
  ) async {
    final settings = FakeSettingsStore()..values[SettingsKeys.uiTheme] = 'dark';
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        overrides: fakeOverrides(source: source, settings: settings),
        child: const TradeLensApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(find.byType(GlassTabBar), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab_settings')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('settings_appearance')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab_portfolio')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('add_position')), findsOneWidget);
  });

  testWidgets('position editor opens on the root navigator, above the '
      'glass tab bar', (tester) async {
    await tester.pumpWidget(scoped());
    await tester.pump();
    await tester.tap(find.byKey(const Key('tab_portfolio')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('add_position')));
    await tester.pumpAndSettle();

    final sheet = find.byType(PositionEditor);
    expect(sheet, findsOneWidget);
    // The sheet's route belongs to the root navigator: the shell's tab
    // bar is not an ancestor of it.
    expect(
      find.ancestor(of: sheet, matching: find.byType(HomeShell)),
      findsNothing,
    );
    final sheetBottom = tester.getBottomLeft(find.byType(BottomSheet)).dy;
    final barTop = tester.getTopLeft(find.byType(GlassTabBar)).dy;
    expect(sheetBottom, greaterThan(barTop));
  });
}
