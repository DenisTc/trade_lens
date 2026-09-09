import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tradelens/providers/app_info.dart';
import 'package:tradelens/router.dart';

/// Root widget: theme with tokens, appearance and language settings,
/// localizations (en, ru), router.
class TradeLensApp extends ConsumerWidget {
  const TradeLensApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(appLocaleSettingProvider).value;
    final themeMode =
        ref.watch(appThemeSettingProvider).value ?? ThemeMode.system;
    return MaterialApp.router(
      title: ref.watch(appNameProvider),
      debugShowCheckedModeBanner: false,
      theme: buildTradeLensTheme(Brightness.light),
      darkTheme: buildTradeLensTheme(Brightness.dark),
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: SharedLocalizations.localizationsDelegates,
      supportedLocales: SharedLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}
