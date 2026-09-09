import 'package:domain/domain.dart';
import 'package:features_settings/features_settings.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('appearance choice persists; system clears it', (tester) async {
    final settings = FakeSettingsStore();
    await tester.pumpWidget(
      testApp(
        overrides: fakeOverrides(
          source: FakeMarketDataSource(),
          settings: settings,
        ),
        home: const AppearanceScreen(),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Match system'), findsOneWidget);
    expect(find.byType(ThemeThumbnail), findsNWidgets(4));

    await tester.tap(find.byKey(const Key('theme_dark')));
    await tester.pump();
    await tester.pump();
    expect(settings.values[SettingsKeys.uiTheme], 'dark');

    await tester.tap(find.byKey(const Key('theme_light')));
    await tester.pump();
    await tester.pump();
    expect(settings.values[SettingsKeys.uiTheme], 'light');

    await tester.tap(find.byKey(const Key('theme_system')));
    await tester.pump();
    await tester.pump();
    expect(settings.values.containsKey(SettingsKeys.uiTheme), isFalse);
  });

  testWidgets('hub shows the current appearance and opens it', (tester) async {
    final settings = FakeSettingsStore()
      ..values[SettingsKeys.uiTheme] = 'light';
    var opened = false;
    await tester.pumpWidget(
      testApp(
        overrides: fakeOverrides(
          source: FakeMarketDataSource(),
          settings: settings,
        ),
        home: SettingsScreen(
          onOpenAppearance: () => opened = true,
          onOpenDataSource: () {},
          onOpenLanguage: () {},
          onOpenAbout: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Light'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings_appearance')));
    expect(opened, isTrue);
  });
}
