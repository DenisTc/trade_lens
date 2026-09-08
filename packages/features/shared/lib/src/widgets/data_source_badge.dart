import 'package:features_shared/src/providers/market_data_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Attribution line at the bottom of market screens, text taken from the
/// active source (`Data: Binance`, `Powered by CoinGecko`).
class DataSourceBadge extends ConsumerWidget {
  const DataSourceBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(marketDataSourceProvider);
    final text = source.value?.attribution ?? '';
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(text, style: style, textAlign: TextAlign.center),
    );
  }
}
