import 'package:clock/clock.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_shared/src/providers/connection.dart';
import 'package:features_shared/src/providers/market_data_source.dart';
import 'package:features_shared/src/providers/quotes.dart';
import 'package:features_shared/src/providers/storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'portfolio.g.dart';

/// Positions from local storage, live.
@riverpod
Stream<List<Position>> positions(Ref ref) =>
    ref.watch(portfolioRepositoryProvider).watchPositions();

/// Instruments of the active source that can price the positions.
/// Positions in a currency the source does not quote get no instrument.
@riverpod
Future<Map<PriceKey, Instrument>> portfolioInstruments(Ref ref) async {
  final source = await ref.watch(marketDataSourceProvider.future);
  final positions = await ref.watch(positionsProvider.future);
  return {
    for (final p in positions)
      priceKeyOf(p): ?source.instrumentFor(p.asset, p.quote),
  };
}

/// Last quotes stored for the active source, read once per source (not on
/// every tick: the valuation only consults them for positions without a
/// live price).
@riverpod
Future<Map<PriceKey, Quote>> storedQuotes(Ref ref) async {
  final source = await ref.watch(marketDataSourceProvider.future);
  final stored = await ref.watch(lastQuoteStoreProvider).readAll(source.id);
  return {for (final q in stored) priceKeyOfQuote(q): q};
}

/// Live valuation.
///
/// Every live quote for a portfolio instrument recomputes it. A position
/// without a live quote yet falls back to the last stored one. The result
/// is "live" only while the socket is connected (or the source polls over
/// REST) and every price came from a live stream; otherwise it is shown
/// "as of" the oldest price used, so a dropped connection never keeps
/// pretending to be live.
@riverpod
Future<PortfolioValuation> portfolioValuation(Ref ref) async {
  final positions = await ref.watch(positionsProvider.future);
  final source = await ref.watch(marketDataSourceProvider.future);
  final instruments = await ref.watch(portfolioInstrumentsProvider.future);
  final stored = await ref.watch(storedQuotesProvider.future);
  final status =
      ref.watch(connectionStatusProvider).value ?? ConnectionStatus.idle;
  final streamsLive =
      !source.capabilities.klineStream || status == ConnectionStatus.connected;

  final prices = <PriceKey, Quote>{};
  var allLive = true;
  DateTime? oldest;
  for (final position in positions) {
    final key = priceKeyOf(position);
    final instrument = instruments[key];
    final live = instrument == null
        ? null
        : ref.watch(quoteProvider(instrument)).value;
    final quote = live ?? stored[key];
    if (quote == null) continue;
    prices[key] = quote;
    if (live == null) allLive = false;
    if (oldest == null || quote.at.isBefore(oldest)) oldest = quote.at;
  }
  final isLive = allLive && streamsLive && prices.isNotEmpty;
  final now = clock.now().toUtc();
  return PortfolioValuation.compute(
    positions: positions,
    quotes: prices,
    asOf: isLive ? now : (oldest ?? now),
    isLive: isLive,
  );
}

/// Commands on the portfolio. Kept out of widgets on purpose.
@riverpod
class PortfolioCommands extends _$PortfolioCommands {
  @override
  void build() {}

  Future<void> add({
    required Asset asset,
    required String quote,
    required Decimal qty,
    required Decimal avgPrice,
    String? note,
  }) {
    final now = clock.now().toUtc();
    return ref
        .read(portfolioRepositoryProvider)
        .upsert(
          Position(
            id: '${asset.id}-$quote-${now.microsecondsSinceEpoch}',
            asset: asset,
            quote: quote,
            qty: qty,
            avgPrice: avgPrice,
            createdAt: now,
            note: note,
          ),
        );
  }

  Future<void> update(Position position) =>
      ref.read(portfolioRepositoryProvider).upsert(position);

  Future<void> remove(String id) =>
      ref.read(portfolioRepositoryProvider).remove(id);
}
