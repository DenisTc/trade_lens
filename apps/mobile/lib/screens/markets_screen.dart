import 'package:features_markets/features_markets.dart' as markets;
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tradelens/router.dart';

/// Route wrapper: binds the feature screen to navigation.
class MarketsScreen extends ConsumerWidget {
  const MarketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return markets.MarketsScreen(
      title: context.l10n.appName,
      onOpenPair: (instrument) =>
          context.go(AppRoutes.pairPath(instrument.symbol)),
    );
  }
}
