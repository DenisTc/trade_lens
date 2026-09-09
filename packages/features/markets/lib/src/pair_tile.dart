import 'package:chart/chart.dart';
import 'package:domain/domain.dart';
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
    final tokens = context.tokens;

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
                color: history.first <= history.last ? tokens.up : tokens.down,
              )
            : const Skeleton(width: 64, height: 20, radius: 4),
      ),
      trailing: switch (quote) {
        AsyncData(:final value) => _QuoteColumn(quote: value),
        AsyncError(:final error) => Tooltip(
          message: '$error',
          child: Icon(Icons.error_outline, color: theme.colorScheme.error),
        ),
        _ => const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Skeleton(width: 84, height: 16),
            SizedBox(height: 6),
            Skeleton(width: 48, height: 12),
          ],
        ),
      },
    );
  }
}

class _QuoteColumn extends StatelessWidget {
  const _QuoteColumn({required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = context.localeTag;
    final change = MoneyFormat.changePct(quote.change24hPct, locale: locale);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          MoneyFormat.price(quote.price, locale: locale),
          style: theme.textTheme.titleMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (change != null)
          Text(
            change,
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.tokens.signed(quote.change24hPct?.sign),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}
