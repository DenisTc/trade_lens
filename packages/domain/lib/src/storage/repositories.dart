import 'package:domain/src/market/candle.dart';
import 'package:domain/src/market/instrument.dart';
import 'package:domain/src/market/interval.dart';
import 'package:domain/src/market/quote.dart';
import 'package:domain/src/portfolio/position.dart';

/// Local persistence contracts. Implemented on Drift in `data_local`;
/// features only ever see these.
abstract interface class PortfolioRepository {
  Stream<List<Position>> watchPositions();
  Future<List<Position>> positions();
  Future<void> upsert(Position position);
  Future<void> remove(String id);
}

/// Last price seen per source and instrument, so the portfolio can be
/// valued offline "as of HH:mm".
abstract interface class LastQuoteStore {
  Future<void> save(Quote quote);
  Future<List<Quote>> readAll(String sourceId);
}

/// Up to 500 candles per `sourceId + instrument + interval`; the network
/// replaces the cache, it never waits for it.
abstract interface class CandleCache {
  Future<List<Candle>> read(Instrument instrument, Interval interval);
  Future<void> write(
    Instrument instrument,
    Interval interval,
    List<Candle> candles,
  );

  /// Drops entries older than [maxAge] (spec: 24 h).
  Future<void> evict({required Duration maxAge, required DateTime now});
}

/// Key–value settings: chosen source, cached region resolution, attribution
/// parameters, consent flags.
abstract interface class SettingsStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Stream<String?> watch(String key);
}

/// Setting keys shared by app and features.
abstract final class SettingsKeys {
  static const manualSource = 'source.manual';
  static const regionResolution = 'source.resolution';
  static const installAttribution = 'attribution.install';
  static const aiConsent = 'ai.consent';
}
