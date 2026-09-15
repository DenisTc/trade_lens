import 'package:backtest/backtest.dart';
import 'package:chart/chart.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_backtest/src/backtest_setup.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart' hide Interval;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Parameters → a run over the candles the pair screen holds → the
/// figures and the trades on the chart. A second set of parameters can
/// be run beside the first. The result is an estimate over historical
/// candles, and the screen says what the model leaves out.
class BacktestScreen extends ConsumerWidget {
  const BacktestScreen({
    required this.instrument,
    super.key,
    this.localTime = true,
  });

  final Instrument instrument;
  final bool localTime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final interval = ref.watch(selectedIntervalProvider);
    final candles = ref.watch(candlesProvider(instrument, interval));
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.backtestTitle),
            Text(instrument.symbol, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
      body: AsyncValueView<List<Candle>>(
        value: candles,
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(candlesProvider(instrument, interval)),
        ),
        data: (list) => list.isEmpty
            ? Center(child: Text(l10n.backtestNoCandles))
            : _Body(
                instrument: instrument,
                interval: interval,
                candles: list,
                localTime: localTime,
              ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.instrument,
    required this.interval,
    required this.candles,
    required this.localTime,
  });

  final Instrument instrument;
  final Interval interval;
  final List<Candle> candles;
  final bool localTime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = context.localeTag;
    final theme = Theme.of(context);
    final t = context.tokens;
    // The starting price seeds the defaults once; the candles keep
    // moving, the form must not.
    final seed = candles.last.close;
    final provider = backtestSetupsProvider(instrument.symbol, seed);
    final setups = ref.watch(provider);
    final notifier = ref.read(provider.notifier);

    return ListView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 24,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Text(
            l10n.backtestCandles(
              candles.length,
              MoneyFormat.time(candles.first.openTime, locale: locale),
              MoneyFormat.time(candles.last.openTime, locale: locale),
            ),
            style: theme.textTheme.bodySmall,
          ),
        ),
        _SetupCard(
          key: const Key('bt_setup_a'),
          label: setups.compare ? l10n.backtestSetA : null,
          setup: setups.a,
          onChanged: notifier.updateA,
          candles: candles,
          interval: interval,
          localTime: localTime,
          prefix: 'a',
        ),
        if (setups.compare)
          _SetupCard(
            key: const Key('bt_setup_b'),
            label: l10n.backtestSetB,
            setup: setups.b,
            onChanged: notifier.updateB,
            candles: candles,
            interval: interval,
            localTime: localTime,
            prefix: 'b',
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: TextButton.icon(
            key: const Key('bt_compare'),
            onPressed: notifier.toggleCompare,
            icon: Icon(setups.compare ? Icons.remove : Icons.add, size: 18),
            label: Text(
              setups.compare ? l10n.backtestCompareOff : l10n.backtestCompare,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text(
            l10n.backtestLimits,
            key: const Key('bt_limits'),
            style: theme.textTheme.bodySmall?.copyWith(color: t.muted),
          ),
        ),
      ],
    );
  }
}

/// One parameter set with its own run button and result underneath.
class _SetupCard extends StatefulWidget {
  const _SetupCard({
    required this.setup,
    required this.onChanged,
    required this.candles,
    required this.interval,
    required this.localTime,
    required this.prefix,
    this.label,
    super.key,
  });

  final BacktestSetup setup;
  final ValueChanged<BacktestSetup> onChanged;
  final List<Candle> candles;
  final Interval interval;
  final bool localTime;
  final String prefix;
  final String? label;

  @override
  State<_SetupCard> createState() => _SetupCardState();
}

class _SetupCardState extends State<_SetupCard> {
  BacktestResult? _result;
  String? _badField;

  void _run() {
    switch (widget.setup.parse()) {
      case Err(:final error):
        setState(() {
          _badField = error;
          _result = null;
        });
      case Ok(:final value):
        setState(() {
          _badField = null;
          _result = runSetup(widget.candles, value);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final t = context.tokens;
    final setup = widget.setup;
    final p = widget.prefix;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.label case final label?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(label, style: theme.textTheme.titleMedium),
                ),
              SegmentedButton<BotKind>(
                key: Key('bt_${p}_kind'),
                segments: [
                  ButtonSegment(
                    value: BotKind.grid,
                    label: Text(l10n.backtestGrid),
                  ),
                  ButtonSegment(
                    value: BotKind.dca,
                    label: Text(l10n.backtestDca),
                  ),
                ],
                selected: {setup.kind},
                onSelectionChanged: (s) =>
                    widget.onChanged(setup.ofKind(s.single)),
              ),
              const SizedBox(height: 12),
              ...switch (setup.kind) {
                BotKind.grid => [
                  _row(context, [
                    _field(p, 'lower', l10n.backtestLower),
                    _field(p, 'upper', l10n.backtestUpper),
                  ]),
                  _row(context, [
                    _field(p, 'levels', l10n.backtestLevels),
                    _field(p, 'investment', l10n.backtestInvestment),
                  ]),
                ],
                BotKind.dca => [
                  _row(context, [
                    _field(p, 'base', l10n.backtestBaseOrder),
                    _field(p, 'safety', l10n.backtestSafetyOrder),
                  ]),
                  _row(context, [
                    _field(p, 'safetyOrders', l10n.backtestSafetyOrders),
                    _field(p, 'step', l10n.backtestStep),
                  ]),
                  _row(context, [
                    _field(p, 'takeProfit', l10n.backtestTakeProfit),
                  ]),
                ],
              },
              _row(context, [_field(p, 'fee', l10n.backtestFee)]),
              const SizedBox(height: 12),
              FilledButton(
                key: Key('bt_${p}_run'),
                onPressed: _run,
                child: Text(l10n.backtestRun),
              ),
              if (_result case final result?) ...[
                const SizedBox(height: 16),
                _ResultView(
                  key: Key('bt_${p}_result'),
                  result: result,
                  candles: widget.candles,
                  interval: widget.interval,
                  localTime: widget.localTime,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, List<Widget> fields) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        for (final (i, f) in fields.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: f),
        ],
      ],
    ),
  );

  Widget _field(String p, String name, String label) => TextFormField(
    key: Key('bt_${p}_$name'),
    initialValue: widget.setup[name],
    decoration: InputDecoration(
      labelText: label,
      errorText: _badField == name ? context.l10n.invalidNumber : null,
      isDense: true,
    ),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (v) => widget.onChanged(widget.setup.with_(name, v)),
  );
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.result,
    required this.candles,
    required this.interval,
    required this.localTime,
    super.key,
  });

  final BacktestResult result;
  final List<Candle> candles;
  final Interval interval;
  final bool localTime;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = context.localeTag;
    final theme = Theme.of(context);
    final t = context.tokens;
    final profit = result.netProfit;
    final sign = profit < Decimal.zero ? '−' : '+';
    final pct = result.netProfitPct;
    final drawdownPct = result.maxDrawdownPct;
    final winRate = result.closedRoundTrips == 0
        ? null
        : (Decimal.fromInt(result.winningRoundTrips * 100) /
                  Decimal.fromInt(result.closedRoundTrips))
              .toDecimal(scaleOnInfinitePrecision: 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                '$sign${MoneyFormat.price(profit.abs(), locale: locale)}',
                key: const Key('bt_net_profit'),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: profit < Decimal.zero ? t.down : t.up,
                ),
              ),
            ),
            if (pct != null)
              ChangeChip(
                sign: profit.sign,
                text: MoneyFormat.changePct(pct, locale: locale),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _metric(theme, l10n.backtestTrades, '${result.tradeCount}'),
        _metric(
          theme,
          l10n.backtestRoundTrips,
          winRate == null
              ? '${result.closedRoundTrips}'
              : '${result.closedRoundTrips} · $winRate %',
        ),
        _metric(
          theme,
          l10n.backtestDrawdown,
          '${MoneyFormat.price(result.maxDrawdown, locale: locale)}'
          '${drawdownPct == null ? '' : ' · ${MoneyFormat.changePct(drawdownPct, locale: locale)}'}',
        ),
        _metric(
          theme,
          l10n.backtestFees,
          MoneyFormat.price(result.fees, locale: locale),
        ),
        _metric(
          theme,
          l10n.backtestFinalEquity,
          MoneyFormat.price(result.finalEquity, locale: locale),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: CandleChart(
            key: const Key('bt_chart'),
            series: CandleSeries.of(candles.map(toChartCandle)),
            interval: chartIntervalFor(interval, candles),
            showVolume: false,
            localTime: localTime,
            emptyLabel: l10n.noData,
            theme: tradeLensChartTheme(context),
            markers: [
              for (final trade in result.trades)
                ChartMarker(
                  at: trade.at,
                  price: trade.price.toDouble(),
                  up: trade.side == TradeSide.buy,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metric(ThemeData theme, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    ),
  );
}
