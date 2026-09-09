import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Last 30 trades, newest on top. Sells (buyer was maker) in red.
class TradeTape extends ConsumerWidget {
  const TradeTape({required this.instrument, super.key});

  final Instrument instrument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trades = ref.watch(recentTradesProvider(instrument));
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final locale = context.localeTag;
    final style = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final timeFormat = DateFormat.Hms(locale);
    return AsyncValueView<List<Trade>>(
      value: trades,
      loading: () => Padding(
        padding: const EdgeInsets.all(12),
        child: Text(context.l10n.waitingForTrades, style: style),
      ),
      data: (list) => Column(
        children: [
          for (final trade in list)
            SizedBox(
              height: 20,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Text(
                      MoneyFormat.price(trade.price, locale: locale),
                      style: style?.copyWith(
                        color: trade.isBuyerMaker ? tokens.down : tokens.up,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      MoneyFormat.quantity(trade.qty, locale: locale),
                      style: style,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      timeFormat.format(trade.at.toLocal()),
                      style: style?.copyWith(color: tokens.muted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
