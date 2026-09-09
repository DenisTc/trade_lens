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

@freezed
abstract class PortfolioValuation with _$PortfolioValuation {
  const factory PortfolioValuation({
    required List<PositionValuation> entries,

    /// Sum of the available values; null when nothing could be valued.
    required Decimal? total,
    required Decimal? totalPnl,
    required Decimal? totalPnlPct,

    /// Time of the prices used.
    required DateTime asOf,

    /// False when prices came from the local `last_quotes` store rather
    /// than a live stream: the UI shows "as of HH:mm".
    required bool isLive,
  }) = _PortfolioValuation;

  const PortfolioValuation._();

  int get unavailableCount => entries.where((e) => !e.isAvailable).length;

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
    var total = Decimal.zero;
    var cost = Decimal.zero;
    var any = false;
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
      total += value;
      cost += position.cost;
      any = true;
    }
    final totalPnl = any ? total - cost : null;
    return PortfolioValuation(
      entries: entries,
      total: any ? total : null,
      totalPnl: totalPnl,
      totalPnlPct: totalPnl == null ? null : _pct(totalPnl, cost),
      asOf: asOf,
      isLive: isLive,
    );
  }

  static Decimal? _pct(Decimal pnl, Decimal cost) => cost == Decimal.zero
      ? null
      : (pnl * Decimal.fromInt(100) / cost).toDecimal(
          scaleOnInfinitePrecision: 4,
        );
}
