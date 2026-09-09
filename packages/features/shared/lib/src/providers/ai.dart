import 'package:domain/domain.dart';
import 'package:features_shared/src/providers/config.dart';
import 'package:features_shared/src/providers/storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ai.g.dart';

/// Keychain-backed secret storage. Declared here without an
/// implementation; the app overrides it (`flutter_secure_storage`), tests
/// use an in-memory fake.
@Riverpod(keepAlive: true)
SecretStore secretStore(Ref ref) =>
    throw UnimplementedError('secretStoreProvider must be overridden');

/// The user's Claude API key, or null when none is stored. The value is
/// never written to settings, logs or Sentry: only this notifier and the
/// transport ever see it.
@Riverpod(keepAlive: true)
class AiApiKey extends _$AiApiKey {
  @override
  Future<String?> build() =>
      ref.watch(secretStoreProvider).read(SecretKeys.anthropicApiKey);

  Future<void> save(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await clear();
      return;
    }
    await ref
        .read(secretStoreProvider)
        .write(SecretKeys.anthropicApiKey, trimmed);
    state = AsyncData(trimmed);
  }

  Future<void> clear() async {
    await ref.read(secretStoreProvider).delete(SecretKeys.anthropicApiKey);
    state = const AsyncData(null);
  }
}

/// Whether the user agreed to send the current pair's candles and order
/// book to the Claude API (spec: consent screen before the first call).
@Riverpod(keepAlive: true)
class AiConsent extends _$AiConsent {
  @override
  Stream<bool> build() => ref
      .watch(settingsStoreProvider)
      .watch(SettingsKeys.aiConsent)
      .map((v) => v == 'true');

  Future<void> grant() =>
      ref.read(settingsStoreProvider).write(SettingsKeys.aiConsent, 'true');

  Future<void> revoke() =>
      ref.read(settingsStoreProvider).delete(SettingsKeys.aiConsent);
}

/// What the summary needs before it can run: the remote flag, a key and
/// consent. The UI explains whichever piece is missing.
enum AiReadiness { disabled, noKey, noConsent, ready }

@riverpod
AiReadiness aiReadiness(Ref ref) {
  if (!ref.watch(aiInsightsEnabledProvider)) return AiReadiness.disabled;
  final key = ref.watch(aiApiKeyProvider).value;
  if (key == null || key.isEmpty) return AiReadiness.noKey;
  if (!(ref.watch(aiConsentProvider).value ?? false)) {
    return AiReadiness.noConsent;
  }
  return AiReadiness.ready;
}
