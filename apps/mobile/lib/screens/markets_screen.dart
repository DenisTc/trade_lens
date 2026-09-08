import 'package:features_markets/features_markets.dart' as markets;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tradelens/providers/app_info.dart';
import 'package:tradelens/router.dart';

/// Route wrapper: binds the feature screen to navigation.
class MarketsScreen extends ConsumerWidget {
  const MarketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return markets.MarketsScreen(
      title: ref.watch(appNameProvider),
      onOpenPair: (instrument) =>
          context.go(AppRoutes.pairPath(instrument.symbol)),
    );
  }
}
