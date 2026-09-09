import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Top-10 bids and asks side by side with depth bars: quantities on the
/// outside, prices meeting in the middle. The whole book is replaced on
/// every snapshot; nothing is patched in place.
class OrderBookView extends ConsumerWidget {
  const OrderBookView({required this.instrument, super.key});

  final Instrument instrument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(orderBookProvider(instrument));
    final tokens = context.tokens;
    final l10n = context.l10n;
    final labelStyle = TradeLensText.mono(
      size: 10,
      weight: FontWeight.w400,
      color: tokens.muted,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Text(l10n.bookVolume.toUpperCase(), style: labelStyle),
              const Spacer(),
              Text(l10n.bookBid.toUpperCase(), style: labelStyle),
              const SizedBox(width: 16),
              Text(l10n.bookAsk.toUpperCase(), style: labelStyle),
              const Spacer(),
              Text(l10n.bookVolume.toUpperCase(), style: labelStyle),
            ],
          ),
        ),
        AsyncValueView<OrderBookSnapshot>(
          value: book,
          loading: () => const _BookSkeleton(),
          data: (snapshot) {
            final maxQty = [
              for (final l in snapshot.bids) l.qty,
              for (final l in snapshot.asks) l.qty,
            ].fold(Decimal.zero, (a, b) => a > b ? a : b);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Side(
                    key: const Key('order_book_bids'),
                    levels: snapshot.bids,
                    maxQty: maxQty,
                    color: tokens.up,
                    alignEnd: true,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _Side(
                    key: const Key('order_book_asks'),
                    levels: snapshot.asks,
                    maxQty: maxQty,
                    color: tokens.down,
                    alignEnd: false,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({
    required this.levels,
    required this.maxQty,
    required this.color,
    required this.alignEnd,
    super.key,
  });

  final List<OrderBookLevel> levels;
  final Decimal maxQty;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final locale = context.localeTag;
    final t = context.tokens;
    final style = TradeLensText.mono(
      size: 12,
      weight: FontWeight.w400,
      color: t.text,
    );
    return Column(
      children: [
        for (final level in levels)
          SizedBox(
            height: 24,
            child: Stack(
              children: [
                Align(
                  alignment: alignEnd
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: maxQty == Decimal.zero
                        ? 0
                        : (level.qty / maxQty).toDouble().clamp(0, 1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    textDirection: alignEnd
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            MoneyFormat.price(level.price, locale: locale),
                            style: style.copyWith(color: color),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            MoneyFormat.quantity(level.qty, locale: locale),
                            style: style.copyWith(color: t.muted),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BookSkeleton extends StatelessWidget {
  const _BookSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < 6; i++)
        const SizedBox(
          height: 24,
          child: Row(
            children: [
              Skeleton(width: 44, height: 10),
              Spacer(),
              Skeleton(width: 60, height: 10),
              SizedBox(width: 16),
              Skeleton(width: 60, height: 10),
              Spacer(),
              Skeleton(width: 44, height: 10),
            ],
          ),
        ),
    ],
  );
}
