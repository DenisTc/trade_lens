import 'package:chart/chart.dart';
import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One 64 px row of the markets list: ticker and name, a sparkline in the
/// middle, price and 24 h chip on the right. Watches the live quote of its
/// instrument and renders the three `AsyncValue` states explicitly.
class PairTile extends ConsumerWidget {
  const PairTile({required this.instrument, super.key, this.onTap});

  final Instrument instrument;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quote = ref.watch(quoteProvider(instrument));
    final history = ref.watch(quoteHistoryProvider(instrument));
    final theme = Theme.of(context);
    final t = context.tokens;

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 108,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PairName(instrument: instrument),
                    const SizedBox(height: 3),
                    Text(
                      instrument.base.name,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 64,
                    height: 24,
                    child: history.length >= 2
                        ? Sparkline(
                            values: [for (final p in history) p.toDouble()],
                            color: history.first <= history.last
                                ? t.up
                                : t.down,
                          )
                        : const Skeleton(width: 64, height: 20, radius: 4),
                  ),
                ),
              ),
              SizedBox(
                width: 112,
                child: switch (quote) {
                  AsyncData(:final value) => _QuoteColumn(quote: value),
                  AsyncError(:final error) => Align(
                    alignment: Alignment.centerRight,
                    child: Tooltip(
                      message: '$error',
                      child: Icon(Icons.error_outline, color: t.down),
                    ),
                  ),
                  _ => const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Skeleton(width: 76, height: 12),
                      SizedBox(height: 8),
                      Skeleton(width: 52, height: 18),
                    ],
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `BTC` in the title weight with `/USDT` smaller and muted. One `Text`
/// so finders and screen readers see `BTC/USDT`.
class PairName extends StatelessWidget {
  const PairName({required this.instrument, super.key, this.size = 16});

  final Instrument instrument;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        text: instrument.base.symbol,
        style: theme.textTheme.titleMedium?.copyWith(fontSize: size),
        children: [
          TextSpan(
            text: '/${instrument.quote}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: size * 0.8125,
              color: context.tokens.muted,
            ),
          ),
        ],
      ),
      maxLines: 1,
    );
  }
}

/// Row-shaped placeholder while the catalog loads.
class PairTileSkeleton extends StatelessWidget {
  const PairTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 64,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          SizedBox(
            width: 108,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 64, height: 12),
                SizedBox(height: 8),
                Skeleton(width: 44, height: 10),
              ],
            ),
          ),
          Expanded(
            child: Center(child: Skeleton(width: 64, height: 20, radius: 4)),
          ),
          SizedBox(
            width: 112,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Skeleton(width: 76, height: 12),
                SizedBox(height: 8),
                Skeleton(width: 52, height: 18),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _QuoteColumn extends StatelessWidget {
  const _QuoteColumn({required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final locale = context.localeTag;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          MoneyFormat.price(quote.price, locale: locale),
          style: TradeLensText.mono(size: 15, color: context.tokens.text),
          maxLines: 1,
        ),
        if (quote.change24hPct != null) ...[
          const SizedBox(height: 4),
          ChangeChip(pct: quote.change24hPct),
        ],
      ],
    );
  }
}
