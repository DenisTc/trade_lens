import 'package:domain/domain.dart';
import 'package:features_markets/src/format.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Last 30 trades, newest on top. Sells (buyer was maker) in red.
class TradeTape extends ConsumerWidget {
  const TradeTape({required this.instrument, super.key});

  final Instrument instrument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trades = ref.watch(recentTradesProvider(instrument));
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return AsyncValueView<List<Trade>>(
      value: trades,
      loading: () => Padding(
        padding: const EdgeInsets.all(12),
        child: Text('Waiting for trades…', style: style),
      ),
      data: (list) => Column(
        children: [
          for (final trade in list)
            SizedBox(
              height: 20,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Text(
                      formatPrice(trade.price),
                      style: style?.copyWith(
                        color: trade.isBuyerMaker
                            ? theme.colorScheme.error
                            : Colors.green.shade600,
                      ),
                    ),
                    const Spacer(),
                    Text(trade.qty.toStringAsFixed(4), style: style),
                    const SizedBox(width: 12),
                    Text(
                      _time(trade.at),
                      style: style?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _time(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }
}
