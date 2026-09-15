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
    this.onExplain,
  });

  final Instrument instrument;
  final bool localTime;
  final void Function(BacktestMetrics metrics)? onExplain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Hold both setups for the entire screen lifetime, including loading.
    final provider = backtestSetupsProvider(instrument.symbol);
    final setups = ref.watch(provider);
    final l10n = context.l10n;
    final interval = ref.watch(selectedIntervalProvider);
    final candles = ref.watch(candlesProvider(instrument, interval));
    final list = candles.value;
    if (!setups.seeded && list != null && list.isNotEmpty) {
      final seed = list.last.close;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) ref.read(provider.notifier).seedIfEmpty(seed);
      });
    }
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
            : !setups.seeded
            ? const SizedBox.shrink()
            : _Body(
                instrument: instrument,
                interval: interval,
                candles: list,
                localTime: localTime,
                onExplain: onExplain,
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
    required this.onExplain,
  });

  final Instrument instrument;
  final Interval interval;
  final List<Candle> candles;
  final bool localTime;
  final void Function(BacktestMetrics metrics)? onExplain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = context.localeTag;
    final theme = Theme.of(context);
    final t = context.tokens;
    final provider = backtestSetupsProvider(instrument.symbol);
    final setups = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    final first = candles.first.openTime;
    final last = candles.last.openTime;
    final sameDay = DateUtils.isSameDay(first.toLocal(), last.toLocal());
    String rangeEnd(DateTime at) => sameDay
        ? MoneyFormat.time(at, locale: locale)
        : '${MoneyFormat.date(at, locale: locale)} '
              '${MoneyFormat.time(at, locale: locale)}';

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
              rangeEnd(first),
              rangeEnd(last),
            ),
            style: theme.textTheme.bodySmall,
          ),
        ),
        _SetupCard(
          key: const Key('bt_setup_a'),
          label: setups.compare ? l10n.backtestSetA : null,
          setup: setups.a,
          onChanged: notifier.updateA,
          onRun: () => notifier.run(candles, interval: interval),
          result: setups.resultA,
          running: setups.runningA,
          candles: candles,
          interval: interval,
          localTime: localTime,
          prefix: 'a',
          onExplain: onExplain == null ? null : _explain,
        ),
        if (setups.compare)
          _SetupCard(
            key: const Key('bt_setup_b'),
            label: l10n.backtestSetB,
            setup: setups.b,
            onChanged: notifier.updateB,
            onRun: () =>
                notifier.run(candles, second: true, interval: interval),
            result: setups.resultB,
            running: setups.runningB,
            candles: candles,
            interval: interval,
            localTime: localTime,
            prefix: 'b',
            onExplain: onExplain == null ? null : _explain,
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

  void _explain(BacktestRun run) => onExplain!(
    BacktestMetrics.fromResult(
      run.result,
      kind: run.setup.kind.name,
      params: switch (run.setup.parse().valueOrNull) {
        final GridParams p => {
          'lower': p.lower.toString(),
          'upper': p.upper.toString(),
          'levels': p.levels.toString(),
          'investment': p.investment.toString(),
          'fee': (p.feeRate * Decimal.fromInt(100)).toString(),
        },
        final DcaParams p => {
          'base': p.baseOrder.toString(),
          'safety': p.safetyOrder.toString(),
          'safetyOrders': p.safetyOrders.toString(),
          'step': p.stepPct.toString(),
          'takeProfit': p.takeProfitPct.toString(),
        },
        _ => throw StateError('A completed run must have valid parameters'),
      },
      symbol: instrument.symbol,
      intervalCode: (run.interval ?? interval).code,
      candleCount: run.candles.length,
      from: run.candles.first.openTime,
      to: run.candles.last.openTime,
    ),
  );
}

/// One parameter set with its own run button and result underneath.
class _SetupCard extends StatefulWidget {
  const _SetupCard({
    required this.setup,
    required this.onChanged,
    required this.onRun,
    required this.result,
    required this.running,
    required this.candles,
    required this.interval,
    required this.localTime,
    required this.prefix,
    this.label,
    this.onExplain,
    super.key,
  });

  final BacktestSetup setup;
  final ValueChanged<BacktestSetup> onChanged;
  final Future<String?> Function() onRun;
  final BacktestRunOutcome? result;
  final bool running;
  final List<Candle> candles;
  final Interval interval;
  final bool localTime;
  final String prefix;
  final String? label;
  final void Function(BacktestRun run)? onExplain;

  @override
  State<_SetupCard> createState() => _SetupCardState();
}

class _SetupCardState extends State<_SetupCard> {
  String? _badField;

  Future<void> _run() async {
    if (widget.running) return;
    final badField = await widget.onRun();
    if (mounted) setState(() => _badField = badField);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final t = context.tokens;
    final setup = widget.setup;
    final p = widget.prefix;
    final stale = switch (widget.result) {
      final BacktestRun run => run.isStale(setup, widget.candles),
      _ => false,
    };
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
                onPressed: widget.running ? null : _run,
                child: widget.running
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.backtestRun),
              ),
              if (widget.result case BacktestRunFailure(:final reason)
                  when !widget.running) ...[
                const SizedBox(height: 16),
                Text(
                  l10n.backtestFailed(reason),
                  key: Key('bt_${p}_error'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              if (widget.result case final BacktestRun run) ...[
                const SizedBox(height: 16),
                if (stale)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      l10n.backtestStale,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                Opacity(
                  key: Key('bt_${p}_result_opacity'),
                  opacity: stale ? 0.5 : 1,
                  child: _ResultView(
                    key: Key('bt_${p}_result'),
                    result: run.result,
                    candles: run.candles,
                    interval: widget.interval,
                    localTime: widget.localTime,
                  ),
                ),
                if (widget.onExplain case final explain?) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: Key('bt_${p}_explain'),
                    onPressed: () => explain(run),
                    child: Text(l10n.backtestExplain),
                  ),
                ],
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
