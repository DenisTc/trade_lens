import 'dart:async';

import 'package:domain/domain.dart';
import 'package:features_shared/src/providers/error_reporter.dart';

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

  @override
  Future<void> evict({
    required Duration maxAge,
    required DateTime now,
    String? keepSourceId,
  }) async => saved.removeWhere(
    (_, q) =>
        now.difference(q.at) > maxAge ||
        (keepSourceId != null && q.instrument.sourceId != keepSourceId),
  );
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
  Future<void> evict({
    required Duration maxAge,
    required DateTime now,
    String? keepSourceId,
  }) async {}
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

  /// Subscribes to changes synchronously on listen, so a write that
  /// happens right after the first value is never missed (an `async*`
  /// generator would only subscribe once the first event was consumed).
  @override
  Stream<String?> watch(String key) {
    late final StreamController<String?> controller;
    StreamSubscription<(String, String?)>? sub;
    controller = StreamController<String?>(
      onListen: () {
        controller.add(values[key]);
        sub = _changes.stream
            .where((c) => c.$1 == key)
            .listen((c) => controller.add(c.$2));
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }
}

/// In-memory [InsightsConfigSource]: emits [current] on listen and every
/// value pushed through [push].
final class FakeInsightsConfigSource implements InsightsConfigSource {
  FakeInsightsConfigSource([InsightsConfig? initial])
    : current = initial ?? defaults;

  static const defaults = InsightsConfig(
    insightsScreenJson:
        '{"schema":1,"children":[{"type":"header","text":{"en":"Fake"}}]}',
    aiInsightsEnabled: false,
    source: InsightsConfigOrigin.defaults,
  );

  InsightsConfig current;
  int refreshes = 0;
  final StreamController<InsightsConfig> _changes =
      StreamController.broadcast();

  void push(InsightsConfig config) {
    current = config;
    _changes.add(config);
  }

  @override
  Stream<InsightsConfig> watch() {
    late final StreamController<InsightsConfig> controller;
    StreamSubscription<InsightsConfig>? sub;
    controller = StreamController<InsightsConfig>(
      onListen: () {
        controller.add(current);
        sub = _changes.stream.listen(controller.add);
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<void> refresh() async => refreshes++;
}

/// Collects handled errors for assertions.
final class RecordingErrorReporter implements ErrorReporter {
  final reports = <(Object error, String? hint)>[];

  @override
  void report(Object error, {StackTrace? stackTrace, String? hint}) =>
      reports.add((error, hint));
}

/// In-memory [SecretStore] for tests; never touches the keychain.
final class FakeSecretStore implements SecretStore {
  FakeSecretStore([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
