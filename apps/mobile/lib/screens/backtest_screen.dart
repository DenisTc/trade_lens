import 'package:features_backtest/features_backtest.dart';
import 'package:features_insights/features_insights.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tradelens/router.dart';

/// Route wrapper for `/p/:symbol/backtest`: the symbol resolved against
/// the active source, the same way the pair screen does it.
class BacktestRouteScreen extends ConsumerWidget {
  const BacktestRouteScreen({required this.symbol, super.key});

  final String symbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instruments = ref.watch(marketInstrumentsProvider);
    final aiEnabled = ref.watch(aiInsightsEnabledProvider);
    final onDeviceAvailable =
        ref.watch(onDeviceAvailabilityProvider).value ==
        OnDeviceAvailability.available;
    return AsyncValueView(
      value: instruments,
      loading: () => Scaffold(
        appBar: AppBar(title: Text(symbol)),
        body: const LoadingView(),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: Text(symbol)),
        body: ErrorView(
          error: error,
          onRetry: ref.read(retryMarketSourceProvider),
        ),
      ),
      data: (list) {
        final match = list.where(
          (i) => i.symbol.toUpperCase() == symbol.toUpperCase(),
        );
        if (match.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: Text(symbol)),
            body: Center(child: Text(context.l10n.pairNotAvailable(symbol))),
          );
        }
        return BacktestScreen(
          instrument: match.first,
          onExplain: aiEnabled || onDeviceAvailable
              ? (metrics) => showBacktestExplanationSheet(
                  context,
                  metrics: metrics,
                  onOpenAiSettings: () => context.go(AppRoutes.settingsAi),
                )
              : null,
        );
      },
    );
  }
}
