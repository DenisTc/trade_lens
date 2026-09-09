import 'package:domain/domain.dart';
import 'package:features_portfolio/src/position_editor.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Positions with live valuation, totals per quote currency and PnL. When
/// any price came from storage or the socket is down the header says
/// "As of HH:mm" instead of "Live".
class PortfolioScreen extends ConsumerStatefulWidget {
  const PortfolioScreen({super.key});

  @override
  ConsumerState<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends ConsumerState<PortfolioScreen> {
  /// Rows dismissed but not yet gone from storage: hidden at once so a
  /// dismissed `Dismissible` never stays in the tree.
  final _removing = <String>{};

  @override
  Widget build(BuildContext context) {
    final valuation = ref.watch(portfolioValuationProvider);
    final l10n = context.l10n;
    final t = context.tokens;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: Column(
        children: [
          ScreenHeader(
            title: l10n.tabPortfolio,
            actions: [
              if (valuation.value case final v?)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: StatusChip(
                    key: const Key('valuation_status'),
                    label: v.isLive
                        ? l10n.valuationLive
                        : l10n.valuationAsOf(
                            MoneyFormat.time(v.asOf, locale: context.localeTag),
                          ),
                    color: v.isLive ? t.up : t.muted,
                    active: v.isLive,
                  ),
                ),
            ],
          ),
          Expanded(
            child: AsyncValueView<PortfolioValuation>(
              value: valuation,
              error: (error, _) => ErrorView(
                error: error,
                onRetry: () => ref.invalidate(portfolioValuationProvider),
              ),
              data: (v) {
                final entries = [
                  for (final e in v.entries)
                    if (!_removing.contains(e.position.id)) e,
                ];
                return ListView(
                  padding: EdgeInsets.only(bottom: bottom + 16),
                  children: [
                    _TotalsHeader(valuation: v, count: entries.length),
                    if (entries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
                        child: Text(
                          l10n.portfolioEmpty,
                          key: const Key('portfolio_empty'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: t.muted),
                        ),
                      )
                    else
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: t.line)),
                        ),
                        child: Column(
                          children: [
                            for (final entry in entries)
                              _PositionTile(
                                key: ValueKey(entry.position.id),
                                entry: entry,
                                onDismissed: () => _remove(entry.position.id),
                              ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: FilledButton.icon(
                        key: const Key('add_position'),
                        onPressed: () => showPositionEditor(context),
                        icon: const Icon(Icons.add, size: 20),
                        label: Text(l10n.addPosition),
                      ),
                    ),
                    const DataSourceBadge(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _remove(String id) async {
    setState(() => _removing.add(id));
    try {
      await ref.read(portfolioCommandsProvider.notifier).remove(id);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _removing.remove(id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _TotalsHeader extends StatelessWidget {
  const _TotalsHeader({required this.valuation, required this.count});

  final PortfolioValuation valuation;
  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = context.localeTag;
    final theme = Theme.of(context);
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (valuation.totals.isEmpty) ...[
            Text(l10n.total, style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Text(
              '—',
              key: const Key('portfolio_total'),
              style: theme.textTheme.displaySmall,
            ),
          ],
          for (final (i, t) in valuation.totals.indexed) ...[
            if (i > 0) const SizedBox(height: 12),
            Text(l10n.totalIn(t.quote), style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 12,
              runSpacing: 6,
              children: [
                Text(
                  MoneyFormat.price(t.total, locale: locale),
                  key: Key(
                    'portfolio_total${valuation.totals.length == 1 ? '' : '_${t.quote}'}',
                  ),
                  style: i == 0
                      ? theme.textTheme.displaySmall
                      : theme.textTheme.headlineMedium,
                ),
                ChangeChip(
                  key: Key('portfolio_pnl_${t.quote}'),
                  sign: t.pnl.sign,
                  text:
                      '${t.pnl.sign < 0 ? '−' : '+'}${MoneyFormat.price(t.pnl.abs(), locale: locale)}'
                      '${t.pnlPct == null ? '' : ' · ${MoneyFormat.changePct(t.pnlPct, locale: locale)}'}',
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                l10n.positionsCount(count),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  l10n.quotesUpdatedAt(
                    MoneyFormat.time(valuation.asOf, locale: locale),
                  ),
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (valuation.unavailableCount > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '· ${l10n.unavailableCount(valuation.unavailableCount)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.warn,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PositionTile extends StatelessWidget {
  const _PositionTile({
    required this.entry,
    required this.onDismissed,
    super.key,
  });

  final PositionValuation entry;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = context.localeTag;
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final p = entry.position;
    return Dismissible(
      key: ValueKey('dismiss-${p.id}'),
      direction: DismissDirection.endToStart,
      background: ColoredBox(
        color: tokens.downBg,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 24),
            child: Icon(Icons.delete_outline, color: tokens.down),
          ),
        ),
      ),
      onDismissed: (_) => onDismissed(),
      child: InkWell(
        onTap: () => showPositionEditor(context, existing: p),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tokens.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: p.asset.symbol,
                        style: theme.textTheme.titleMedium,
                        children: [
                          TextSpan(
                            text: '/${p.quote}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 13,
                              color: tokens.muted,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${MoneyFormat.quantity(p.qty, locale: locale)} × '
                      '${MoneyFormat.price(p.avgPrice, locale: locale)}'
                      '${p.note == null || p.note!.isEmpty ? '' : ' · ${p.note}'}',
                      style: TradeLensText.mono(
                        size: 12,
                        weight: FontWeight.w400,
                        color: tokens.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (entry.isAvailable)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      MoneyFormat.price(entry.value!, locale: locale),
                      style: TradeLensText.mono(size: 15, color: tokens.text),
                    ),
                    const SizedBox(height: 4),
                    ChangeChip(
                      pct: entry.pnlPct,
                      sign: entry.pnl?.sign,
                      text: entry.pnlPct == null
                          ? MoneyFormat.price(entry.pnl!, locale: locale)
                          : null,
                    ),
                  ],
                )
              else
                Tooltip(
                  message: l10n.priceUnavailable,
                  child: Icon(Icons.help_outline, color: tokens.warn),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
