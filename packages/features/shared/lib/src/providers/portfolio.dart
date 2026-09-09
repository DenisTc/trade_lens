import 'package:clock/clock.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
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

/// Live valuation. Every live quote arriving for a portfolio instrument
/// recomputes the valuation; instruments without a live quote yet fall
/// back to the last stored quote, and the whole valuation is marked
/// non-live (shown as "as of HH:mm") while any price came from storage.
@riverpod
Future<PortfolioValuation> portfolioValuation(Ref ref) async {
  final positions = await ref.watch(positionsProvider.future);
  final source = await ref.watch(marketDataSourceProvider.future);
  final instruments = await ref.watch(portfolioInstrumentsProvider.future);

  final live = <PriceKey, Quote>{};
  for (final entry in instruments.entries) {
    final quote = ref.watch(quoteProvider(entry.value)).value;
    if (quote != null) live[entry.key] = quote;
  }

  // Stored prices make the valuation "as of" the oldest one used.
  DateTime? oldestStored;
  final prices = <PriceKey, Quote>{...live};
  final missing = positions.map(priceKeyOf).where((k) => !live.containsKey(k));
  if (missing.isNotEmpty) {
    final stored = await ref.watch(lastQuoteStoreProvider).readAll(source.id);
    for (final quote in stored) {
      final key = priceKeyOfQuote(quote);
      if (!missing.contains(key)) continue;
      prices[key] = quote;
      if (oldestStored == null || quote.at.isBefore(oldestStored)) {
        oldestStored = quote.at;
      }
    }
  }
  return PortfolioValuation.compute(
    positions: positions,
    quotes: prices,
    asOf: oldestStored ?? clock.now().toUtc(),
    isLive: oldestStored == null,
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
