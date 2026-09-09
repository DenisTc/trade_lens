import 'package:features_markets/features_markets.dart' as markets;
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Route wrapper for `/p/:symbol`: resolves the symbol against the active
/// source's instruments (deep links and SDUI buttons carry only a symbol).
class PairScreen extends ConsumerWidget {
  const PairScreen({required this.symbol, super.key});

  final String symbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instruments = ref.watch(marketInstrumentsProvider);
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
        return markets.PairScreen(instrument: match.first);
      },
    );
  }
}
