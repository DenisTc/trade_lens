import 'dart:async';
import 'dart:io';

import 'package:data_config/data_config.dart';
import 'package:domain/domain.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeClient implements RemoteConfigClient {
  final values = <String, Object>{};
  final origins = <String, RemoteValueOrigin>{};
  final updates = StreamController<Set<String>>.broadcast();
  final pending = <String, Object>{};
  Map<String, Object>? defaults;
  Duration? fetchTimeout;
  Duration? minimumFetchInterval;
  int fetches = 0;
  Exception? fetchError;

  /// When set, a fetch waits for this completer instead of finishing.
  Completer<void>? fetchGate;

  @override
  Future<void> configure({
    required Duration fetchTimeout,
    required Duration minimumFetchInterval,
    required Map<String, Object> defaults,
  }) async {
    this.fetchTimeout = fetchTimeout;
    this.minimumFetchInterval = minimumFetchInterval;
    this.defaults = defaults;
    for (final e in defaults.entries) {
      values.putIfAbsent(e.key, () => e.value);
      origins.putIfAbsent(e.key, () => RemoteValueOrigin.defaults);
    }
  }

  @override
  Future<bool> fetchAndActivate() async {
    fetches++;
    if (fetchGate case final gate?) await gate.future;
    if (fetchError case final Exception error) throw error;
    return await activate();
  }

  @override
  Future<bool> activate() async {
    if (pending.isEmpty) return false;
    values.addAll(pending);
    for (final k in pending.keys) {
      origins[k] = RemoteValueOrigin.remote;
    }
    pending.clear();
    return true;
  }

  @override
  Stream<Set<String>> get onUpdated => updates.stream;

  @override
  String getString(String key) => values[key] as String? ?? '';

  @override
  bool getBool(String key) => values[key] as bool? ?? false;

  @override
  RemoteValueOrigin originOf(String key) =>
      origins[key] ?? RemoteValueOrigin.static;
}

final class _SlowConfigureClient extends FakeClient {
  _SlowConfigureClient(this.gate);

  final Completer<void> gate;

  @override
  Future<void> configure({
    required Duration fetchTimeout,
    required Duration minimumFetchInterval,
    required Map<String, Object> defaults,
  }) async {
    await gate.future;
    await super.configure(
      fetchTimeout: fetchTimeout,
      minimumFetchInterval: minimumFetchInterval,
      defaults: defaults,
    );
  }
}

void main() {
  const defaults = InsightsConfig(
    insightsScreenJson: '{"schema":1,"children":[]}',
    aiInsightsEnabled: false,
    source: InsightsConfigOrigin.defaults,
  );

  Future<void> settle([int turns = 5]) async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  late FakeClient client;
  late RemoteInsightsConfigSource source;

  setUp(() {
    client = FakeClient();
    source = RemoteInsightsConfigSource(
      client: client,
      defaults: defaults,
      fetchTimeout: const Duration(milliseconds: 50),
      minimumFetchInterval: Duration.zero,
    );
  });

  tearDown(() => source.dispose());

  test('emits defaults first, then the fetched remote values', () async {
    client.pending['insights_screen'] = '{"schema":1,"children":[1]}';
    client.pending['ai_insights_enabled'] = true;
    final seen = <InsightsConfig>[];
    final sub = source.watch().listen(seen.add);
    await settle();
    await sub.cancel();

    expect(seen.first, defaults);
    expect(seen.last.source, InsightsConfigOrigin.remote);
    expect(seen.last.insightsScreenJson, '{"schema":1,"children":[1]}');
    expect(seen.last.aiInsightsEnabled, isTrue);
    expect(client.defaults?['insights_screen'], defaults.insightsScreenJson);
    expect(client.minimumFetchInterval, Duration.zero);
    expect(client.fetches, 1);
  });

  test('a failed fetch keeps the defaults; the stream never errors', () async {
    client.fetchError = const SocketException('offline');
    final seen = <InsightsConfig>[];
    final errors = <Object>[];
    final sub = source.watch().listen(seen.add, onError: errors.add);
    await settle();
    await sub.cancel();
    expect(seen, [defaults]);
    expect(errors, isEmpty);
  });

  test('a fetch slower than the timeout is abandoned', () {
    fakeAsync((async) {
      client
        ..fetchGate = Completer<void>()
        ..pending['ai_insights_enabled'] = true;
      final seen = <InsightsConfig>[];
      final sub = source.watch().listen(seen.add);
      async.flushMicrotasks();
      expect(client.fetches, 1, reason: 'the fetch started');
      var refreshed = false;
      unawaited(source.refresh().then((_) => refreshed = true));
      async.elapse(const Duration(seconds: 1));
      expect(refreshed, isFalse, reason: 'still within the timeout');
      async.elapse(const Duration(seconds: 2));
      expect(refreshed, isTrue, reason: 'refresh completes on timeout');
      expect(seen, [defaults]);
      // The late completion is ignored: nothing new is emitted.
      client.fetchGate!.complete();
      async.flushMicrotasks();
      expect(seen, [defaults]);
      unawaited(sub.cancel());
      async.flushMicrotasks();
    });
  });

  test('a realtime update during a fetch is not lost', () async {
    client.fetchGate = Completer<void>();
    final seen = <InsightsConfig>[];
    final sub = source.watch().listen(seen.add);
    await settle();
    client.pending['insights_screen'] = '{"schema":1,"children":[5]}';
    client.updates.add({'insights_screen'});
    await settle();
    client.fetchGate!.complete();
    await settle();
    await sub.cancel();
    expect(seen.last.insightsScreenJson, '{"schema":1,"children":[5]}');
    expect(
      seen.where((c) => c.insightsScreenJson.contains('[5]')),
      hasLength(1),
    );
  });

  test('dispose completes watch() streams', () async {
    final done = source.watch().toList();
    await settle();
    await source.dispose();
    expect(await done, [defaults]);
    expect(await source.watch().toList(), [defaults]);
  });

  test('dispose during configure prevents the fetch', () async {
    final gate = Completer<void>();
    final slow = _SlowConfigureClient(gate);
    final s = RemoteInsightsConfigSource(
      client: slow,
      defaults: defaults,
      minimumFetchInterval: Duration.zero,
    );
    final sub = s.watch().listen((_) {});
    await settle();
    await s.dispose();
    gate.complete();
    await settle();
    await sub.cancel();
    expect(slow.fetches, 0);
  });

  test('concurrent refresh calls share one fetch', () async {
    client.fetchGate = Completer<void>();
    final sub = source.watch().listen((_) {});
    await settle();
    final second = source.refresh();
    final third = source.refresh();
    expect(client.fetches, 1);
    client.fetchGate!.complete();
    await Future.wait([second, third]);
    await sub.cancel();
    expect(client.fetches, 1);
  });

  test('a realtime update is activated and emitted', () async {
    final seen = <InsightsConfig>[];
    final sub = source.watch().listen(seen.add);
    await settle();

    client.pending['insights_screen'] = '{"schema":1,"children":[2]}';
    client.updates.add({'insights_screen'});
    await settle();
    await sub.cancel();

    expect(seen.last.insightsScreenJson, '{"schema":1,"children":[2]}');
    expect(seen.last.source, InsightsConfigOrigin.remote);
  });

  test('cancel then relisten keeps receiving realtime updates', () async {
    final first = source.watch().listen((_) {});
    await settle();
    await first.cancel();
    await settle();
    expect(client.updates.hasListener, isFalse);

    final seen = <InsightsConfig>[];
    final second = source.watch().listen(seen.add);
    await settle();
    expect(client.updates.hasListener, isTrue);
    client.pending['insights_screen'] = '{"schema":1,"children":[3]}';
    client.updates.add({'insights_screen'});
    await settle();
    await second.cancel();
    expect(seen.last.insightsScreenJson, '{"schema":1,"children":[3]}');
  });

  test('a late listener gets the current value, not the defaults', () async {
    client.pending['insights_screen'] = '{"schema":1,"children":[4]}';
    final first = source.watch().listen((_) {});
    await settle();
    final seen = <InsightsConfig>[];
    final second = source.watch().listen(seen.add);
    await settle();
    await first.cancel();
    await second.cancel();
    expect(seen.first.insightsScreenJson, '{"schema":1,"children":[4]}');
  });

  test('identical values are not re-emitted', () async {
    final seen = <InsightsConfig>[];
    final sub = source.watch().listen(seen.add);
    await settle();
    client.updates.add({'nothing'});
    await settle();
    await sub.cancel();
    expect(seen, [defaults]);
  });

  test('dispose during a pending fetch drops its result', () async {
    client
      ..fetchGate = Completer<void>()
      ..pending['ai_insights_enabled'] = true;
    final seen = <InsightsConfig>[];
    final done = source.watch().listen(seen.add).asFuture<void>();
    await settle();
    await source.dispose();
    client.fetchGate!.complete();
    await settle();
    await done;
    expect(seen, [defaults]);
    expect(client.updates.hasListener, isFalse);
  });

  test('DefaultsInsightsConfigSource emits its defaults once', () async {
    expect(
      await const DefaultsInsightsConfigSource(defaults).watch().toList(),
      [defaults],
    );
  });
}
