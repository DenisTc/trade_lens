import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Top-10 bids and asks side by side with depth bars. The whole book is
/// replaced on every snapshot; nothing is patched in place.
class OrderBookView extends ConsumerWidget {
  const OrderBookView({required this.instrument, super.key});

  final Instrument instrument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(orderBookProvider(instrument));
    final tokens = context.tokens;
    return AsyncValueView<OrderBookSnapshot>(
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
            const SizedBox(width: 8),
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
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Column(
      children: [
        for (final level in levels)
          SizedBox(
            height: 20,
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
                    child: ColoredBox(color: color.withValues(alpha: 0.15)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    textDirection: alignEnd
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    children: [
                      Text(
                        MoneyFormat.price(level.price, locale: locale),
                        style: style?.copyWith(color: color),
                      ),
                      const Spacer(),
                      Text(
                        MoneyFormat.quantity(level.qty, locale: locale),
                        style: style,
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
  Widget build(BuildContext context) => const SizedBox(
    height: 200,
    child: Center(child: CircularProgressIndicator.adaptive()),
  );
}
