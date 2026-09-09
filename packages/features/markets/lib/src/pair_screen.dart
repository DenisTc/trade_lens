import 'package:chart/chart.dart';
import 'package:domain/domain.dart';
import 'package:features_markets/src/chart_mapping.dart';
import 'package:features_markets/src/connection_dot.dart';
import 'package:features_markets/src/order_book_view.dart';
import 'package:features_markets/src/pair_tile.dart';
import 'package:features_markets/src/trade_tape.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart' hide Interval;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One pair: live price, candlestick chart, order book and trade tape.
/// Parts the active source cannot provide are hidden, not faked
/// (`Capabilities`): the REST fallback shows a prices-only chart without
/// volume, interval selector, book or tape.
class PairScreen extends ConsumerWidget {
  const PairScreen({
    required this.instrument,
    super.key,
    this.localTime = true,
    this.onMoveSummary,
  });

  final Instrument instrument;

  /// Opens the AI move summary; null hides the button (flag off, or a
  /// build without the feature). The feature itself lives elsewhere, so
  /// this package never depends on the Claude client.
  final VoidCallback? onMoveSummary;

  /// Time axis in local time; golden tests pass false.
  final bool localTime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities =
        ref.watch(marketDataSourceProvider).value?.capabilities ??
        Capabilities.pricesOnly;
    final interval = ref.watch(selectedIntervalProvider);
    final candles = ref.watch(candlesProvider(instrument, interval));
    final series = ref.watch(chartSeriesProvider(instrument, interval));
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            PairName(instrument: instrument, size: 17),
            Text(instrument.base.name, style: theme.textTheme.labelSmall),
          ],
        ),
        actions: const [ConnectionDot(), SizedBox(width: 12)],
      ),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 16,
        ),
        children: [
          _PriceHeader(instrument: instrument),
          if (onMoveSummary != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: OutlinedButton.icon(
                key: const Key('move_summary'),
                onPressed: onMoveSummary,
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text(l10n.aiSummaryTitle),
              ),
            ),
          if (capabilities.intervals.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: IntervalPills(
                key: const Key('interval_selector'),
                intervals: capabilities.intervals,
                selected: interval,
                onSelected: (iv) =>
                    ref.read(selectedIntervalProvider.notifier).value = iv,
              ),
            ),
          SizedBox(
            height: 290,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
              child: AsyncValueView<CandleSeries>(
                value: series,
                error: (error, _) => ErrorView(
                  error: error,
                  onRetry: () =>
                      ref.invalidate(candlesProvider(instrument, interval)),
                ),
                data: (chartSeries) => CandleChart(
                  key: const Key('pair_chart'),
                  series: chartSeries,
                  interval: chartIntervalFor(
                    interval,
                    candles.value ?? const [],
                  ),
                  showVolume: capabilities.volume,
                  localTime: localTime,
                  emptyLabel: l10n.noData,
                  theme: tradeLensChartTheme(context),
                ),
              ),
            ),
          ),
          if (!capabilities.volume)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(
                l10n.pricesOnlyNote(
                  chartIntervalFor(interval, candles.value ?? const []).label ??
                      interval.code,
                ),
                key: const Key('prices_only_note'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (capabilities.orderBook) ...[
            const SizedBox(height: 10),
            SectionHeader(l10n.orderBook),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: OrderBookView(instrument: instrument),
            ),
          ],
          if (capabilities.trades) ...[
            const SizedBox(height: 8),
            SectionHeader(l10n.trades, trailing: l10n.tradesLast(30)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TradeTape(instrument: instrument),
            ),
          ],
          const SizedBox(height: 16),
          const DataSourceBadge(),
        ],
      ),
    );
  }
}

/// Chart colours from the tokens: rise and fall, accent crosshair with an
/// accent price tag, hairline grid, mono axis labels.
CandleChartTheme tradeLensChartTheme(BuildContext context) {
  final t = context.tokens;
  return CandleChartTheme(
    up: t.up,
    down: t.down,
    grid: t.line,
    axisText: t.muted,
    crosshair: t.accent,
    crosshairLabelBackground: t.accent,
    crosshairLabelText: t.onAccent,
    fontFamily: TradeLensFonts.mono,
  );
}

/// Interval choice as pills; the selected one wears the accent ring.
class IntervalPills extends StatelessWidget {
  const IntervalPills({
    required this.intervals,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final Iterable<Interval> intervals;
  final Interval selected;
  final ValueChanged<Interval> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final iv in intervals)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Semantics(
              button: true,
              selected: iv == selected,
              child: InkWell(
                onTap: () => onSelected(iv),
                borderRadius: BorderRadius.circular(22),
                child: SizedBox(
                  height: 44,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      constraints: const BoxConstraints(minHeight: 32),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: iv == selected ? t.accentBg : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: iv == selected ? t.accent : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        iv.code,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: iv == selected ? t.accentInk : t.muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PriceHeader extends ConsumerWidget {
  const _PriceHeader({required this.instrument});

  final Instrument instrument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quote = ref.watch(quoteProvider(instrument));
    final theme = Theme.of(context);
    final locale = context.localeTag;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: switch (quote) {
        AsyncData(:final value) => Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                MoneyFormat.price(value.price, locale: locale),
                key: const Key('pair_price'),
                style: theme.textTheme.displaySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (value.change24hPct != null) ...[
              const SizedBox(width: 12),
              ChangeChip(pct: value.change24hPct),
            ],
          ],
        ),
        AsyncError(:final error) => Text(
          '$error',
          style: theme.textTheme.bodySmall?.copyWith(
            color: context.tokens.down,
          ),
        ),
        _ => const SizedBox(
          height: 44,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Skeleton(width: 180, height: 30),
          ),
        ),
      },
    );
  }
}
