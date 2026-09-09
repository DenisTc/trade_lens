import 'package:domain/domain.dart';
import 'package:features_shared/src/providers/storage.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'locale.g.dart';

/// Language chosen in Settings. `null` follows the system locale.
@Riverpod(keepAlive: true)
class AppLocaleSetting extends _$AppLocaleSetting {
  @override
  Stream<Locale?> build() => ref
      .watch(settingsStoreProvider)
      .watch(SettingsKeys.uiLocale)
      .map((code) => code == null ? null : Locale(code));

  Future<void> choose(Locale? locale) async {
    final store = ref.read(settingsStoreProvider);
    if (locale == null) {
      await store.delete(SettingsKeys.uiLocale);
    } else {
      await store.write(SettingsKeys.uiLocale, locale.languageCode);
    }
  }
}
