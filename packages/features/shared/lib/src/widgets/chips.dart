import 'package:core/core.dart';
import 'package:features_shared/src/format.dart';
import 'package:features_shared/src/l10n_ext.dart';
import 'package:features_shared/src/theme/tokens.dart';
import 'package:features_shared/src/widgets/lens_ring.dart';
import 'package:flutter/material.dart';

/// Signed percentage on a 12 % tint: `+2,14 %` green, `−3,42 %` red. Mono,
/// 22 px tall, radius 6. [text] overrides the formatted percentage when a
/// caller wants to show an absolute amount next to it.
class ChangeChip extends StatelessWidget {
  const ChangeChip({super.key, this.pct, this.text, this.sign});

  final Decimal? pct;
  final String? text;

  /// Sign to colour by when [text] is given without [pct].
  final num? sign;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final label =
        text ?? MoneyFormat.changePct(pct, locale: context.localeTag) ?? '—';
    final s = sign ?? pct?.sign;
    return Container(
      constraints: const BoxConstraints(minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: t.signedBg(s),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TradeLensText.mono(size: 12, color: t.signed(s)),
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

/// Lens ring plus a short word: "Live" with a filled ring, "As of 12:40"
/// with an empty grey ring.
class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.label,
    required this.color,
    super.key,
    this.active = true,
  });

  final String label;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      LensRing(size: 16, color: color, dot: active, gap: false),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: color),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}
