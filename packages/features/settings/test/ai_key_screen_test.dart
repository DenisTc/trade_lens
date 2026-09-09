import 'package:domain/domain.dart';
import 'package:features_settings/features_settings.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeSecretStore secrets;
  late FakeSettingsStore settings;

  Widget app({bool aiEnabled = true}) => testApp(
    overrides: fakeOverrides(
      source: FakeMarketDataSource(),
      secrets: secrets,
      settings: settings,
      config: FakeInsightsConfigSource(
        InsightsConfig(
          insightsScreenJson: '{"schema":1,"children":[]}',
          aiInsightsEnabled: aiEnabled,
          source: InsightsConfigOrigin.remote,
        ),
      ),
    ),
    home: const AiKeyScreen(),
  );

  setUp(() {
    secrets = FakeSecretStore();
    settings = FakeSettingsStore();
  });

  testWidgets('saves the key, shows it masked, and clears it', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();
    expect(find.text('No key saved'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('ai_key_field')),
      'sk-ant-api03-secret-value-1234',
    );
    await tester.tap(find.byKey(const Key('ai_key_save')));
    await tester.pump();
    await tester.pump();

    expect(
      secrets.values[SecretKeys.anthropicApiKey],
      'sk-ant-api03-secret-value-1234',
    );
    // Masked on screen; the raw key is never rendered back.
    final status = tester
        .widget<Text>(find.byKey(const Key('ai_key_status')))
        .data!;
    expect(status, contains('sk-ant-'));
    expect(status, contains('1234'));
    expect(status, isNot(contains('secret-value')));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('ai_key_field')))
          .controller!
          .text,
      isEmpty,
    );

    await tester.tap(find.byKey(const Key('ai_key_clear')));
    await tester.pump();
    await tester.pump();
    expect(secrets.values.containsKey(SecretKeys.anthropicApiKey), isFalse);
    expect(find.text('No key saved'), findsOneWidget);
  });

  testWidgets('the consent switch writes and clears the setting', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('ai_consent_switch')));
    await tester.pump();
    await tester.pump();
    expect(settings.values[SettingsKeys.aiConsent], 'true');

    await tester.tap(find.byKey(const Key('ai_consent_switch')));
    await tester.pump();
    await tester.pump();
    expect(settings.values.containsKey(SettingsKeys.aiConsent), isFalse);
  });

  testWidgets('a remotely disabled feature says so', (tester) async {
    await tester.pumpWidget(app(aiEnabled: false));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('ai_disabled_note')), findsOneWidget);
  });

  testWidgets('the hub row reflects what is still missing', (tester) async {
    var opened = false;
    Widget hub() => testApp(
      overrides: fakeOverrides(
        source: FakeMarketDataSource(),
        secrets: secrets,
        settings: settings,
        config: FakeInsightsConfigSource(
          const InsightsConfig(
            insightsScreenJson: '{"schema":1,"children":[]}',
            aiInsightsEnabled: true,
            source: InsightsConfigOrigin.remote,
          ),
        ),
      ),
      home: SettingsScreen(
        onOpenAi: () => opened = true,
        onOpenDataSource: () {},
        onOpenLanguage: () {},
        onOpenAbout: () {},
      ),
    );

    await tester.pumpWidget(hub());
    await tester.pump();
    await tester.pump();
    expect(find.text('Your own Claude API key'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_ai')));
    expect(opened, isTrue);
  });
}
