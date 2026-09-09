import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer container({
    SecretStore? secrets,
    SettingsStore? settings,
    bool aiEnabled = true,
  }) {
    final c = ProviderContainer(
      retry: noRetry,
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
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> settle([int turns = 6]) async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('the API key round-trips through the secret store', () async {
    final secrets = FakeSecretStore();
    final c = container(secrets: secrets);
    expect(await c.read(aiApiKeyProvider.future), isNull);

    await c.read(aiApiKeyProvider.notifier).save('  sk-ant-abc  ');
    expect(secrets.values[SecretKeys.anthropicApiKey], 'sk-ant-abc');
    expect(c.read(aiApiKeyProvider).value, 'sk-ant-abc');

    await c.read(aiApiKeyProvider.notifier).clear();
    expect(secrets.values.containsKey(SecretKeys.anthropicApiKey), isFalse);
    expect(c.read(aiApiKeyProvider).value, isNull);
  });

  test('saving an empty key clears it instead of storing blanks', () async {
    final secrets = FakeSecretStore({SecretKeys.anthropicApiKey: 'sk-old'});
    final c = container(secrets: secrets);
    await c.read(aiApiKeyProvider.future);
    await c.read(aiApiKeyProvider.notifier).save('   ');
    expect(secrets.values.containsKey(SecretKeys.anthropicApiKey), isFalse);
  });

  test('consent is stored in settings and can be revoked', () async {
    final settings = FakeSettingsStore();
    final c = container(settings: settings);
    final sub = c.listen(aiConsentProvider, (_, _) {});
    addTearDown(sub.close);
    expect(await c.read(aiConsentProvider.future), isFalse);

    await c.read(aiConsentProvider.notifier).grant();
    await settle();
    expect(settings.values[SettingsKeys.aiConsent], 'true');
    expect(c.read(aiConsentProvider).value, isTrue);

    await c.read(aiConsentProvider.notifier).revoke();
    await settle();
    expect(settings.values.containsKey(SettingsKeys.aiConsent), isFalse);
    expect(c.read(aiConsentProvider).value, isFalse);
  });

  test('readiness names the missing piece, in order', () async {
    final off = container(aiEnabled: false);
    final sub0 = off.listen(aiReadinessProvider, (_, _) {});
    addTearDown(sub0.close);
    await settle();
    expect(off.read(aiReadinessProvider), AiReadiness.disabled);

    final secrets = FakeSecretStore();
    final settings = FakeSettingsStore();
    final c = container(secrets: secrets, settings: settings);
    final sub = c.listen(aiReadinessProvider, (_, _) {});
    addTearDown(sub.close);
    await settle();
    expect(c.read(aiReadinessProvider), AiReadiness.noKey);

    await c.read(aiApiKeyProvider.notifier).save('sk-ant-abc');
    await settle();
    expect(c.read(aiReadinessProvider), AiReadiness.noConsent);

    await c.read(aiConsentProvider.notifier).grant();
    await settle();
    expect(c.read(aiReadinessProvider), AiReadiness.ready);
  });
}
