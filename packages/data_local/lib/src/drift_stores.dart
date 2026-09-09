import 'package:core/core.dart';
import 'package:data_local/src/database.dart';
import 'package:domain/domain.dart';
import 'package:drift/drift.dart';

/// Drift implementations of the domain storage contracts. Mapping is
/// explicit and lives here; domain types never see Drift rows.
final class DriftPortfolioRepository implements PortfolioRepository {
  DriftPortfolioRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Position>> watchPositions() =>
      (_db.select(_db.positions)
            ..orderBy([(p) => OrderingTerm.asc(p.createdAt)]))
          .watch()
          .map((rows) => rows.map(_toPosition).toList());

  @override
  Future<List<Position>> positions() async =>
      (await (_db.select(
            _db.positions,
          )..orderBy([(p) => OrderingTerm.asc(p.createdAt)])).get())
          .map(_toPosition)
          .toList();

  @override
  Future<void> upsert(Position position) => _db
      .into(_db.positions)
      .insertOnConflictUpdate(
        PositionsCompanion.insert(
          id: position.id,
          assetId: position.asset.id,
          assetSymbol: position.asset.symbol,
          assetName: position.asset.name,
          quote: position.quote,
          qty: position.qty.toString(),
          avgPrice: position.avgPrice.toString(),
          createdAt: position.createdAt,
          note: Value(position.note),
        ),
      );

  @override
  Future<void> remove(String id) =>
      (_db.delete(_db.positions)..where((p) => p.id.equals(id))).go();

  static Position _toPosition(PositionRow row) => Position(
    id: row.id,
    asset: Asset(id: row.assetId, symbol: row.assetSymbol, name: row.assetName),
    quote: row.quote,
    qty: Decimal.parse(row.qty),
    avgPrice: Decimal.parse(row.avgPrice),
    // Drift reads unix timestamps back as local time; the domain is UTC.
    createdAt: row.createdAt.toUtc(),
    note: row.note,
  );
}

final class DriftLastQuoteStore implements LastQuoteStore {
  DriftLastQuoteStore(this._db);

  final AppDatabase _db;

  @override
  Future<void> save(Quote quote) => _db
      .into(_db.lastQuotes)
      .insertOnConflictUpdate(
        LastQuotesCompanion.insert(
          sourceId: quote.instrument.sourceId,
          symbol: quote.instrument.symbol,
          assetId: quote.instrument.base.id,
          assetSymbol: quote.instrument.base.symbol,
          assetName: quote.instrument.base.name,
          quote: quote.instrument.quote,
          price: quote.price.toString(),
          change24hPct: Value(quote.change24hPct?.toString()),
          at: quote.at,
        ),
      );

  @override
  Future<List<Quote>> readAll(String sourceId) async {
    final rows = await (_db.select(
      _db.lastQuotes,
    )..where((q) => q.sourceId.equals(sourceId))).get();
    return [
      for (final row in rows)
        Quote(
          instrument: Instrument(
            sourceId: row.sourceId,
            symbol: row.symbol,
            base: Asset(
              id: row.assetId,
              symbol: row.assetSymbol,
              name: row.assetName,
            ),
            quote: row.quote,
          ),
          price: Decimal.parse(row.price),
          change24hPct: row.change24hPct == null
              ? null
              : Decimal.parse(row.change24hPct!),
          at: row.at.toUtc(),
        ),
    ];
  }

  @override
  Future<void> evict({
    required Duration maxAge,
    required DateTime now,
    String? keepSourceId,
  }) =>
      (_db.delete(_db.lastQuotes)..where((q) {
            final old = q.at.isSmallerThanValue(now.subtract(maxAge));
            return keepSourceId == null
                ? old
                : old | q.sourceId.equals(keepSourceId).not();
          }))
          .go();
}

final class DriftCandleCache implements CandleCache {
  DriftCandleCache(this._db, {this.limit = 500});

  final AppDatabase _db;
  final int limit;

  @override
  Future<List<Candle>> read(Instrument instrument, Interval interval) async {
    final rows =
        await (_db.select(_db.candleCacheRows)
              ..where(
                (c) =>
                    c.sourceId.equals(instrument.sourceId) &
                    c.symbol.equals(instrument.symbol) &
                    c.interval.equals(interval.code),
              )
              ..orderBy([(c) => OrderingTerm.asc(c.openTime)]))
            .get();
    return [
      for (final row in rows)
        Candle(
          openTime: DateTime.fromMillisecondsSinceEpoch(
            row.openTime,
            isUtc: true,
          ),
          open: Decimal.parse(row.open),
          high: Decimal.parse(row.high),
          low: Decimal.parse(row.low),
          close: Decimal.parse(row.close),
          volume: row.volume == null ? null : Decimal.parse(row.volume!),
        ),
    ];
  }

  /// Replaces the cached window with the newest [limit] candles, in one
  /// transaction and one batch: 500 rows must not mean 500 statements.
  @override
  Future<void> write(
    Instrument instrument,
    Interval interval,
    List<Candle> candles,
  ) {
    final keep = candles.length <= limit
        ? candles
        : candles.sublist(candles.length - limit);
    final now = DateTime.now().toUtc();
    return _db.transaction(() async {
      await (_db.delete(_db.candleCacheRows)..where(
            (c) =>
                c.sourceId.equals(instrument.sourceId) &
                c.symbol.equals(instrument.symbol) &
                c.interval.equals(interval.code),
          ))
          .go();
      await _db.batch((batch) {
        batch.insertAll(_db.candleCacheRows, [
          for (final c in keep)
            CandleCacheRowsCompanion.insert(
              sourceId: instrument.sourceId,
              symbol: instrument.symbol,
              interval: interval.code,
              openTime: c.openTime.millisecondsSinceEpoch,
              open: c.open.toString(),
              high: c.high.toString(),
              low: c.low.toString(),
              close: c.close.toString(),
              volume: Value(c.volume?.toString()),
              storedAt: now,
            ),
        ]);
      });
    });
  }

  @override
  Future<void> evict({
    required Duration maxAge,
    required DateTime now,
    String? keepSourceId,
  }) =>
      (_db.delete(_db.candleCacheRows)..where((c) {
            final old = c.storedAt.isSmallerThanValue(now.subtract(maxAge));
            return keepSourceId == null
                ? old
                : old | c.sourceId.equals(keepSourceId).not();
          }))
          .go();
}

final class DriftSettingsStore implements SettingsStore {
  DriftSettingsStore(this._db);

  final AppDatabase _db;

  @override
  Future<String?> read(String key) async => (await (_db.select(
    _db.settings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  @override
  Future<void> write(String key, String value) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));

  @override
  Future<void> delete(String key) =>
      (_db.delete(_db.settings)..where((s) => s.key.equals(key))).go();

  @override
  Stream<String?> watch(String key) =>
      (_db.select(_db.settings)..where((s) => s.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => row?.value);
}
