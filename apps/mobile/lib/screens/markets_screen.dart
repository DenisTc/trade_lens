import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tradelens/providers/app_info.dart';
import 'package:tradelens/router.dart';

/// Placeholder until `features_markets` lands on day 3.
class MarketsScreen extends ConsumerWidget {
  const MarketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(ref.watch(appNameProvider))),
      body: Center(
        child: FilledButton(
          onPressed: () => context.go(AppRoutes.pairPath('BTCUSDT')),
          child: const Text('BTC/USDT'),
        ),
      ),
    );
  }
}
