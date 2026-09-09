import 'dart:async';

import 'package:domain/domain.dart';

/// In-memory storage doubles for feature tests.
final class FakePortfolioRepository implements PortfolioRepository {
  final Map<String, Position> _rows = {};
  final StreamController<List<Position>> _changes =
      StreamController.broadcast();

  List<Position> get _sorted =>
      _rows.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Stream<List<Position>> watchPositions() async* {
    yield _sorted;
    yield* _changes.stream;
  }

  @override
  Future<List<Position>> positions() async => _sorted;

  @override
  Future<void> upsert(Position position) async {
    _rows[position.id] = position;
    _changes.add(_sorted);
  }

  @override
  Future<void> remove(String id) async {
    _rows.remove(id);
    _changes.add(_sorted);
  }
}

final class FakeLastQuoteStore implements LastQuoteStore {
  final Map<String, Quote> saved = {};

  @override
  Future<void> save(Quote quote) async =>
      saved['${quote.instrument.sourceId}/${quote.instrument.symbol}'] = quote;

  @override
  Future<List<Quote>> readAll(String sourceId) async => [
    for (final q in saved.values)
      if (q.instrument.sourceId == sourceId) q,
  ];
}

final class FakeCandleCache implements CandleCache {
  final Map<String, List<Candle>> entries = {};

  String _key(Instrument i, Interval iv) =>
      '${i.sourceId}/${i.symbol}/${iv.code}';

  @override
  Future<List<Candle>> read(Instrument instrument, Interval interval) async =>
      entries[_key(instrument, interval)] ?? const [];

  @override
  Future<void> write(
    Instrument instrument,
    Interval interval,
    List<Candle> candles,
  ) async => entries[_key(instrument, interval)] = candles;

  @override
  Future<void> evict({required Duration maxAge, required DateTime now}) async {}
}

final class FakeSettingsStore implements SettingsStore {
  final Map<String, String> values = {};
  final StreamController<(String, String?)> _changes =
      StreamController.broadcast();

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
    _changes.add((key, value));
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
    _changes.add((key, null));
  }

  @override
  Stream<String?> watch(String key) async* {
    yield values[key];
    yield* _changes.stream.where((c) => c.$1 == key).map((c) => c.$2);
  }
}
