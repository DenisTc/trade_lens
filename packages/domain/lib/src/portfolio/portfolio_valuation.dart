import 'package:core/core.dart';
import 'package:domain/src/market/quote.dart';
import 'package:domain/src/portfolio/position.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'portfolio_valuation.freezed.dart';

/// Key of a price the portfolio can use: asset + quote currency.
typedef PriceKey = ({String assetId, String quote});

PriceKey priceKeyOf(Position p) => (assetId: p.asset.id, quote: p.quote);

PriceKey priceKeyOfQuote(Quote q) =>
    (assetId: q.instrument.base.id, quote: q.instrument.quote);

@freezed
abstract class PositionValuation with _$PositionValuation {
  const factory PositionValuation({
    required Position position,

    /// Null when no comparable quote exists (other quote currency, source
    /// without the pair, nothing cached).
    required Decimal? price,
    required Decimal? value,
    required Decimal? pnl,
    required Decimal? pnlPct,
  }) = _PositionValuation;

  const PositionValuation._();

  bool get isAvailable => price != null;
}

/// Totals of the valued positions in one quote currency. USDT and USD are
/// never added together; each currency gets its own line.
@freezed
abstract class CurrencyTotals with _$CurrencyTotals {
  const factory CurrencyTotals({
    required String quote,
    required Decimal total,
    required Decimal cost,
    required Decimal pnl,
    required Decimal? pnlPct,
  }) = _CurrencyTotals;
}

@freezed
abstract class PortfolioValuation with _$PortfolioValuation {
  const factory PortfolioValuation({
    required List<PositionValuation> entries,

    /// One entry per quote currency that has at least one valued position,
    /// sorted by currency. Empty when nothing could be valued.
    required List<CurrencyTotals> totals,

    /// Time of the prices used (oldest one when not live).
    required DateTime asOf,

    /// False when any price came from the local `last_quotes` store or the
    /// live connection is gone: the UI shows "as of HH:mm".
    required bool isLive,
  }) = _PortfolioValuation;

  const PortfolioValuation._();

  /// Pure function: positions × prices → valuation. No I/O, no clocks.
  ///
  /// A position is valued only by a quote in its own quote currency; a
  /// USDT position never gets a USD price silently. Percentages use the
  /// cost basis and are null when the cost is zero.
  factory PortfolioValuation.compute({
    required List<Position> positions,
    required Map<PriceKey, Quote> quotes,
    required DateTime asOf,
    required bool isLive,
  }) {
    final entries = <PositionValuation>[];
    final total = <String, Decimal>{};
    final cost = <String, Decimal>{};
    for (final position in positions) {
      final quote = quotes[priceKeyOf(position)];
      if (quote == null) {
        entries.add(
          PositionValuation(
            position: position,
            price: null,
            value: null,
            pnl: null,
            pnlPct: null,
          ),
        );
        continue;
      }
      final value = position.qty * quote.price;
      final pnl = value - position.cost;
      entries.add(
        PositionValuation(
          position: position,
          price: quote.price,
          value: value,
          pnl: pnl,
          pnlPct: _pct(pnl, position.cost),
        ),
      );
      total[position.quote] = (total[position.quote] ?? Decimal.zero) + value;
      cost[position.quote] =
          (cost[position.quote] ?? Decimal.zero) + position.cost;
    }
    final totals = [
      for (final quote in total.keys.toList()..sort())
        CurrencyTotals(
          quote: quote,
          total: total[quote]!,
          cost: cost[quote]!,
          pnl: total[quote]! - cost[quote]!,
          pnlPct: _pct(total[quote]! - cost[quote]!, cost[quote]!),
        ),
    ];
    return PortfolioValuation(
      entries: entries,
      totals: totals,
      asOf: asOf,
      isLive: isLive,
    );
  }

  int get unavailableCount => entries.where((e) => !e.isAvailable).length;

  static Decimal? _pct(Decimal pnl, Decimal cost) => cost == Decimal.zero
      ? null
      : (pnl * Decimal.fromInt(100) / cost).toDecimal(
          scaleOnInfinitePrecision: 4,
        );
}
