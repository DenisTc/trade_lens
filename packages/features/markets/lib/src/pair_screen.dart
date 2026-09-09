import 'package:chart/chart.dart';
import 'package:domain/domain.dart';
import 'package:features_markets/src/chart_mapping.dart';
import 'package:features_markets/src/connection_dot.dart';
import 'package:features_markets/src/format.dart';
import 'package:features_markets/src/order_book_view.dart';
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
  });

  final Instrument instrument;

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

    return Scaffold(
      appBar: AppBar(
        title: Text(instrument.displayName),
        actions: const [ConnectionDot()],
      ),
      body: ListView(
        children: [
          _PriceHeader(instrument: instrument),
          if (capabilities.intervals.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<Interval>(
                key: const Key('interval_selector'),
                segments: [
                  for (final iv in capabilities.intervals)
                    ButtonSegment(value: iv, label: Text(iv.code)),
                ],
                selected: {interval},
                showSelectedIcon: false,
                onSelectionChanged: (set) =>
                    ref.read(selectedIntervalProvider.notifier).value =
                        set.first,
              ),
            ),
          SizedBox(
            height: 280,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 0, 0),
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
                ),
              ),
            ),
          ),
          if (!capabilities.volume)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                'Prices only: ${chartIntervalFor(interval, candles.value ?? const []).label} candles, no volume',
                key: const Key('prices_only_note'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (capabilities.orderBook) ...[
            const _SectionTitle('Order book'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: OrderBookView(instrument: instrument),
            ),
          ],
          if (capabilities.trades) ...[
            const _SectionTitle('Trades'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TradeTape(instrument: instrument),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
      bottomNavigationBar: const SafeArea(child: DataSourceBadge()),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: switch (quote) {
        AsyncData(:final value) => Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              formatPrice(value.price),
              key: const Key('pair_price'),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 12),
            if (formatChangePct(value.change24hPct) case final change?)
              Text(
                change,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: (value.change24hPct?.sign ?? 0) >= 0
                      ? Colors.green.shade600
                      : theme.colorScheme.error,
                ),
              ),
          ],
        ),
        AsyncError(:final error) => Text(
          '$error',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        _ => const SizedBox(
          height: 40,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            ),
          ),
        ),
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}
