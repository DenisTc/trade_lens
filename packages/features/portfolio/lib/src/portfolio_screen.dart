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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabPortfolio)),
      body: AsyncValueView<PortfolioValuation>(
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
          if (entries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.portfolioEmpty,
                  key: const Key('portfolio_empty'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            children: [
              _TotalsHeader(valuation: v),
              for (final entry in entries)
                _PositionTile(
                  key: ValueKey(entry.position.id),
                  entry: entry,
                  onDismissed: () => _remove(entry.position.id),
                ),
              const SizedBox(height: 88),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add_position'),
        onPressed: () => showPositionEditor(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.addPosition),
      ),
      bottomNavigationBar: const SafeArea(child: DataSourceBadge()),
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
  const _TotalsHeader({required this.valuation});

  final PortfolioValuation valuation;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = context.localeTag;
    final theme = Theme.of(context);
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.total, style: theme.textTheme.labelLarge),
          if (valuation.totals.isEmpty)
            Text(
              '—',
              key: const Key('portfolio_total'),
              style: theme.textTheme.headlineMedium,
            ),
          for (final t in valuation.totals) ...[
            Text(
              '${MoneyFormat.price(t.total, locale: locale)} ${t.quote}',
              key: Key(
                'portfolio_total${valuation.totals.length == 1 ? '' : '_${t.quote}'}',
              ),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              '${l10n.pnl} ${t.pnl.sign < 0 ? '' : '+'}${MoneyFormat.price(t.pnl, locale: locale)}'
              '${t.pnlPct == null ? '' : ' (${MoneyFormat.changePct(t.pnlPct, locale: locale)})'}',
              key: Key('portfolio_pnl_${t.quote}'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: tokens.signed(t.pnl.sign),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                valuation.isLive ? Icons.bolt : Icons.schedule,
                size: 14,
                color: valuation.isLive ? tokens.up : tokens.warn,
              ),
              const SizedBox(width: 4),
              Text(
                valuation.isLive
                    ? l10n.valuationLive
                    : l10n.valuationAsOf(
                        MoneyFormat.time(valuation.asOf, locale: locale),
                      ),
                key: const Key('valuation_status'),
                style: theme.textTheme.bodySmall?.copyWith(color: tokens.muted),
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
        color: theme.colorScheme.errorContainer,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 24),
            child: Icon(
              Icons.delete_outline,
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ),
      ),
      onDismissed: (_) => onDismissed(),
      child: ListTile(
        onTap: () => showPositionEditor(context, existing: p),
        title: Text('${p.asset.symbol}/${p.quote}'),
        subtitle: Text(
          '${MoneyFormat.quantity(p.qty, locale: locale)} × '
          '${MoneyFormat.price(p.avgPrice, locale: locale)}'
          '${p.note == null || p.note!.isEmpty ? '' : ' · ${p.note}'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: entry.isAvailable
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    MoneyFormat.price(entry.value!, locale: locale),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    MoneyFormat.changePct(entry.pnlPct, locale: locale) ??
                        MoneyFormat.price(entry.pnl!, locale: locale),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.signed(entry.pnl?.sign),
                    ),
                  ),
                ],
              )
            : Tooltip(
                message: l10n.priceUnavailable,
                child: Icon(Icons.help_outline, color: tokens.warn),
              ),
      ),
    );
  }
}
