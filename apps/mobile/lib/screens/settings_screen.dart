import 'package:features_settings/features_settings.dart' as settings;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tradelens/di/market_di.dart';
import 'package:tradelens/router.dart';

/// Route wrappers for the settings hub and its sub-screens.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => settings.SettingsScreen(
    onOpenAppearance: () => context.go(AppRoutes.settingsAppearance),
    onOpenAi: () => context.go(AppRoutes.settingsAi),
    onOpenDataSource: () => context.go(AppRoutes.settingsSource),
    onOpenLanguage: () => context.go(AppRoutes.settingsLanguage),
    onOpenAbout: () => context.go(AppRoutes.settingsAbout),
  );
}

/// "Check source now" re-runs the region resolver and rebuilds the live
/// stack.
class DataSourceScreen extends ConsumerWidget {
  const DataSourceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      settings.DataSourceScreen(
        onCheckSource: () => ref.read(recheckSourceProvider)(),
      );
}
