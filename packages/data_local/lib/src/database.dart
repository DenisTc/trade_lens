import 'package:drift/drift.dart';

part 'database.g.dart';

/// Manual holdings. Money columns are TEXT: `Decimal` round-trips through
/// its string form, `REAL` would not.
@DataClassName('PositionRow')
class Positions extends Table {
  TextColumn get id => text()();
  TextColumn get assetId => text()();
  TextColumn get assetSymbol => text()();
  TextColumn get assetName => text()();
  TextColumn get quote => text()();
  TextColumn get qty => text()();
  TextColumn get avgPrice => text()();
  DateTimeColumn get createdAt => dateTime()();

  /// Added in schema v2.
  TextColumn get note => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Up to 500 candles per source, instrument and interval.
class CandleCacheRows extends Table {
  @override
  String get tableName => 'candle_cache';

  TextColumn get sourceId => text()();
  TextColumn get symbol => text()();
  TextColumn get interval => text()();
  IntColumn get openTime => integer()();
  TextColumn get open => text()();
  TextColumn get high => text()();
  TextColumn get low => text()();
  TextColumn get close => text()();
  TextColumn get volume => text().nullable()();
  DateTimeColumn get storedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {sourceId, symbol, interval, openTime};
}

/// Last price per source and instrument for the offline valuation.
class LastQuotes extends Table {
  @override
  String get tableName => 'last_quotes';

  TextColumn get sourceId => text()();
  TextColumn get symbol => text()();
  TextColumn get assetId => text()();
  TextColumn get assetSymbol => text()();
  TextColumn get assetName => text()();
  TextColumn get quote => text()();
  TextColumn get price => text()();
  TextColumn get change24hPct => text().nullable()();
  DateTimeColumn get at => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {sourceId, symbol};
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(tables: [Positions, CandleCacheRows, LastQuotes, Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  /// v1 → v2: `positions.note`. Creating the schema is not a migration;
  /// this step is, and `test/migration_test.dart` proves rows survive it.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.addColumn(positions, positions.note);
    },
  );
}
