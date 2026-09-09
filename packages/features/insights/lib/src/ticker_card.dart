import 'package:chart/chart.dart';
import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The one SDUI node with live data: a pair card with name, sparkline,
/// price and 24 h chip. Resolves the symbol against the active source's
/// instruments; an unknown symbol shows the symbol and "not available".
class TickerCard extends ConsumerWidget {
  const TickerCard({
    required this.symbol,
    super.key,
    this.showSparkline = true,
    this.onTap,
  });

  final String symbol;
  final bool showSparkline;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instruments = ref.watch(marketInstrumentsProvider).value;
    final match = instruments
        ?.where((i) => i.symbol.toUpperCase() == symbol.toUpperCase())
        .firstOrNull;
    final t = context.tokens;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: Key('ticker_card_$symbol'),
        onTap: match == null ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 84),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.line),
          ),
          child: match == null
              ? _Unavailable(symbol: symbol, loading: instruments == null)
              : _Live(instrument: match, showSparkline: showSparkline),
        ),
      ),
    );
  }
}

class _Live extends ConsumerWidget {
  const _Live({required this.instrument, required this.showSparkline});

  final Instrument instrument;
  final bool showSparkline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quote = ref.watch(quoteProvider(instrument));
    final history = ref.watch(quoteHistoryProvider(instrument));
    final t = context.tokens;
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  text: instrument.base.symbol,
                  style: theme.textTheme.titleMedium,
                  children: [
                    TextSpan(
                      text: '/${instrument.quote}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        color: t.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(instrument.base.name, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        if (showSparkline)
          SizedBox(
            width: 72,
            height: 28,
            child: history.length >= 2
                ? Sparkline(
                    values: [for (final p in history) p.toDouble()],
                    color: history.first <= history.last ? t.up : t.down,
                  )
                : const Skeleton(width: 72, height: 20, radius: 4),
          ),
        const SizedBox(width: 16),
        SizedBox(
          width: 112,
          child: switch (quote) {
            AsyncData(:final value) => Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  MoneyFormat.price(value.price, locale: context.localeTag),
                  style: TradeLensText.mono(size: 15, color: t.text),
                  maxLines: 1,
                ),
                if (value.change24hPct != null) ...[
                  const SizedBox(height: 4),
                  ChangeChip(pct: value.change24hPct),
                ],
              ],
            ),
            AsyncError(:final error) => Align(
              alignment: Alignment.centerRight,
              child: Tooltip(
                message: '$error',
                child: Icon(Icons.error_outline, color: t.down),
              ),
            ),
            _ => const Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Skeleton(width: 76, height: 12),
                SizedBox(height: 8),
                Skeleton(width: 52, height: 18),
              ],
            ),
          },
        ),
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.symbol, required this.loading});

  final String symbol;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(symbol, style: theme.textTheme.titleMedium)),
        if (loading)
          const Skeleton(width: 76, height: 12)
        else
          Text(
            context.l10n.pairNotAvailable(symbol),
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.end,
          ),
      ],
    );
  }
}
