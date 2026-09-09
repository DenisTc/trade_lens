import 'package:domain/domain.dart';
import 'package:features_shared/src/providers/storage.dart';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'theme.g.dart';

/// Appearance chosen in Settings; `system` follows the phone.
@Riverpod(keepAlive: true)
class AppThemeSetting extends _$AppThemeSetting {
  @override
  Stream<ThemeMode> build() => ref
      .watch(settingsStoreProvider)
      .watch(SettingsKeys.uiTheme)
      .map(themeModeFromStorage);

  Future<void> choose(ThemeMode mode) async {
    final store = ref.read(settingsStoreProvider);
    if (mode == ThemeMode.system) {
      await store.delete(SettingsKeys.uiTheme);
    } else {
      await store.write(SettingsKeys.uiTheme, mode.name);
    }
  }
}

ThemeMode themeModeFromStorage(String? value) => switch (value) {
  'dark' => ThemeMode.dark,
  'light' => ThemeMode.light,
  _ => ThemeMode.system,
};
