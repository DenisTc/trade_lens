import 'package:domain/domain.dart';
import 'package:features_settings/features_settings.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hub shows three rows and opens them', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      testApp(
        overrides: fakeOverrides(source: FakeMarketDataSource()),
        home: SettingsScreen(
          onOpenDataSource: () => opened.add('source'),
          onOpenLanguage: () => opened.add('language'),
          onOpenAbout: () => opened.add('about'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('settings_source')));
    await tester.tap(find.byKey(const Key('settings_language')));
    await tester.tap(find.byKey(const Key('settings_about')));
    expect(opened, ['source', 'language', 'about']);
    expect(find.text('System default'), findsOneWidget);
  });

  testWidgets('choosing a source persists it; auto clears it', (tester) async {
    final settings = FakeSettingsStore();
    await tester.pumpWidget(
      testApp(
        overrides: fakeOverrides(
          source: FakeMarketDataSource(),
          settings: settings,
        ),
        home: const DataSourceScreen(),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('source_coingecko')));
    await tester.pump();
    await tester.pump();
    expect(settings.values[SettingsKeys.manualSource], 'coingecko');

    await tester.tap(find.byKey(const Key('source_auto')));
    await tester.pump();
    await tester.pump();
    expect(settings.values.containsKey(SettingsKeys.manualSource), isFalse);
  });

  testWidgets('language choice persists and switches strings', (tester) async {
    final settings = FakeSettingsStore();
    await tester.pumpWidget(
      testApp(
        overrides: fakeOverrides(
          source: FakeMarketDataSource(),
          settings: settings,
        ),
        home: const LanguageScreen(),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('language_ru')));
    await tester.pump();
    await tester.pump();
    expect(settings.values[SettingsKeys.uiLocale], 'ru');
    await tester.tap(find.byKey(const Key('language_system')));
    await tester.pump();
    await tester.pump();
    expect(settings.values.containsKey(SettingsKeys.uiLocale), isFalse);
  });

  testWidgets('about shows terms date and links', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 2200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        overrides: fakeOverrides(source: FakeMarketDataSource()),
        home: const AboutScreen(),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Terms last checked'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Terms of use'), findsOneWidget);
    expect(find.text('CoinGecko'), findsWidgets);
  });

  test('SourceChoice.fromStorage falls back to auto', () {
    expect(SourceChoice.fromStorage(null), SourceChoice.auto);
    expect(SourceChoice.fromStorage('binance_us'), SourceChoice.binanceUs);
    expect(SourceChoice.fromStorage('junk'), SourceChoice.auto);
  });
}
