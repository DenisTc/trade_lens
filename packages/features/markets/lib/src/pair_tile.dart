import 'package:chart/chart.dart';
import 'package:domain/domain.dart';
import 'package:features_markets/src/format.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One row of the markets list. Watches the live quote of its instrument
/// and renders the three `AsyncValue` states explicitly.
class PairTile extends ConsumerWidget {
  const PairTile({required this.instrument, super.key, this.onTap});

  final Instrument instrument;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quote = ref.watch(quoteProvider(instrument));
    final history = ref.watch(quoteHistoryProvider(instrument));
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      title: Text(instrument.displayName),
      subtitle: Text(instrument.base.name),
      leading: SizedBox(
        width: 64,
        height: 28,
        child: history.length >= 2
            ? Sparkline(
                values: [for (final p in history) p.toDouble()],
                color: _trendColor(history.first <= history.last, theme),
              )
            : const SizedBox.shrink(),
      ),
      trailing: switch (quote) {
        AsyncData(:final value) => _QuoteColumn(quote: value),
        AsyncError(:final error) => Tooltip(
          message: '$error',
          child: Icon(Icons.error_outline, color: theme.colorScheme.error),
        ),
        _ => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        ),
      },
    );
  }

  static Color _trendColor(bool up, ThemeData theme) =>
      up ? Colors.green.shade600 : theme.colorScheme.error;
}

class _QuoteColumn extends StatelessWidget {
  const _QuoteColumn({required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = formatChangePct(quote.change24hPct);
    final positive = (quote.change24hPct?.sign ?? 0) >= 0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          formatPrice(quote.price),
          style: theme.textTheme.titleMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (change != null)
          Text(
            change,
            style: theme.textTheme.bodySmall?.copyWith(
              color: positive ? Colors.green.shade600 : theme.colorScheme.error,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}
