import 'package:features_settings/features_settings.dart' as settings;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tradelens/di/market_di.dart';

/// Route wrapper: "Check source now" re-runs the region resolver and
/// rebuilds the live stack.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return settings.SettingsScreen(
      onCheckSource: () => ref.read(recheckSourceProvider)(),
    );
  }
}
