import 'dart:async';

import 'package:domain/domain.dart';
import 'package:features_settings/features_settings.dart';
import 'package:features_shared/features_shared.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeSecretStore secrets;
  late FakeSettingsStore settings;

  Widget app({
    bool aiEnabled = true,
    OnDeviceAvailability availability = OnDeviceAvailability.unsupportedDevice,
    Future<OnDeviceAvailability> Function()? availabilityFactory,
    _FakeOnDeviceLlm? onDeviceLlm,
  }) => testApp(
    overrides: [
      ...fakeOverrides(
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
        onDeviceLlm:
            onDeviceLlm ??
            _FakeOnDeviceLlm(
              status: availability,
              availabilityFactory: availabilityFactory,
            ),
      ),
      appLanguageCodeProvider.overrideWithValue('en'),
    ],
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

  for (final (availability, text) in [
    (OnDeviceAvailability.available, 'Available — summaries run on this phone'),
    (
      OnDeviceAvailability.unsupportedDevice,
      'This phone cannot run it. Android support is not wired yet',
    ),
    (
      OnDeviceAvailability.unsupportedOs,
      'Needs iOS 26. Android support is not wired yet',
    ),
    (OnDeviceAvailability.modelNotReady, 'The model is still downloading'),
    (OnDeviceAvailability.disabled, 'Apple Intelligence is off in Settings'),
    (
      OnDeviceAvailability.unsupportedLanguage,
      'Not available for this language on this phone',
    ),
  ]) {
    testWidgets('shows the $availability on-device status', (tester) async {
      await tester.pumpWidget(app(availability: availability));
      await tester.pump();

      expect(find.text('On-device model'), findsOneWidget);
      expect(find.text(text), findsOneWidget);
    });
  }

  testWidgets('shows progress while checking on-device availability', (
    tester,
  ) async {
    final pending = Completer<OnDeviceAvailability>();
    await tester.pumpWidget(app(availabilityFactory: () => pending.future));

    expect(find.text('Checking availability…'), findsOneWidget);
  });

  testWidgets('shows a probe failure instead of a download status', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        availabilityFactory: () =>
            Future.error(StateError('platform channel failed')),
      ),
    );
    await tester.pump();

    expect(find.text('Could not check availability'), findsOneWidget);
    expect(find.text('The model is still downloading'), findsNothing);
  });

  testWidgets('re-probes on-device availability when the screen opens', (
    tester,
  ) async {
    final llm = _FakeOnDeviceLlm(status: OnDeviceAvailability.available);

    await tester.pumpWidget(app(onDeviceLlm: llm));
    await tester.pump();

    expect(llm.availabilityCalls, 2);
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

final class _FakeOnDeviceLlm implements OnDeviceLlmApi {
  _FakeOnDeviceLlm({required this.status, this.availabilityFactory});

  final OnDeviceAvailability status;
  final Future<OnDeviceAvailability> Function()? availabilityFactory;
  int availabilityCalls = 0;

  @override
  Future<OnDeviceAvailability> availability(String languageCode) {
    availabilityCalls++;
    return availabilityFactory?.call() ?? Future.value(status);
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<String> generate({
    required String system,
    required String prompt,
    required String languageCode,
    required int maxOutputChars,
  }) async => 'unused';

  @override
  Future<String> runtimeName() async => 'fake';
}
