import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Last 30 trades, newest on top: time, price (sells red), quantity.
class TradeTape extends ConsumerWidget {
  const TradeTape({required this.instrument, super.key});

  final Instrument instrument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trades = ref.watch(recentTradesProvider(instrument));
    final tokens = context.tokens;
    final locale = context.localeTag;
    final style = TradeLensText.mono(
      size: 12,
      weight: FontWeight.w400,
      color: tokens.text,
    );
    final timeFormat = DateFormat.Hms(locale);
    return AsyncValueView<List<Trade>>(
      value: trades,
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          context.l10n.waitingForTrades,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      data: (list) => Column(
        children: [
          for (final trade in list)
            SizedBox(
              height: 24,
              child: Row(
                children: [
                  Text(
                    timeFormat.format(trade.at.toLocal()),
                    style: style.copyWith(color: tokens.muted),
                  ),
                  const Spacer(),
                  Text(
                    MoneyFormat.price(trade.price, locale: locale),
                    style: style.copyWith(
                      color: trade.isBuyerMaker ? tokens.down : tokens.up,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    MoneyFormat.quantity(trade.qty, locale: locale),
                    style: style,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
