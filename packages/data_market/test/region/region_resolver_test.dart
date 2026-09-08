// Tests drive futures with fakeAsync and pump them by hand.
// ignore_for_file: discarded_futures

import 'package:clock/clock.dart';
import 'package:data_market/data_market.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

/// Scripted probe: a queue of outcomes per candidate id, consumed in order;
/// the last one repeats.
final class ScriptedProbe implements SourceProbe {
  ScriptedProbe(this.script);

  final Map<String, List<ProbeOutcome>> script;
  final List<String> calls = [];

  @override
  Future<ProbeOutcome> probe(SourceCandidate candidate) async {
    calls.add(candidate.id);
    final queue = script[candidate.id]!;
    return queue.length > 1 ? queue.removeAt(0) : queue.single;
  }
}

SourceCandidate _c(String id, String sourceId) => SourceCandidate(
  id: id,
  sourceId: sourceId,
  restPing: Uri.parse('https://$id.test/ping'),
  wsProbe: Uri.parse('wss://$id.test/stream'),
);

void main() {
  final global = _c('binance_global', 'binance');
  final vision = _c('binance_vision', 'binance');
  final us = _c('binance_us', 'binance_us');
  final gecko = SourceCandidate(
    id: 'coingecko',
    sourceId: 'coingecko',
    restPing: Uri.parse('https://gecko.test/ping'),
  );
  final start = DateTime.utc(2026, 9, 8, 12);

  RegionResolver build(
    ScriptedProbe probe, {
    required List<Duration> sleeps,
    required FakeAsync async,
    ResolutionCache? cache,
  }) => RegionResolver(
    probe: probe,
    candidates: [global, vision, us],
    fallback: gecko,
    cache: cache,
    clock: Clock(() => start.add(async.elapsed)),
    sleep: (d) async {
      sleeps.add(d);
      async.elapse(d);
    },
  );

  test('first candidate ok → direct, nothing else probed', () {
    fakeAsync((async) {
      final probe = ScriptedProbe({
        'binance_global': [ProbeOutcome.ok],
      });
      final sleeps = <Duration>[];
      Resolution? result;
      build(
        probe,
        sleeps: sleeps,
        async: async,
      ).resolve().then((r) => result = r);
      async.flushMicrotasks();

      expect(result!.candidateId, 'binance_global');
      expect(result!.reason, ResolutionReason.direct);
      expect(probe.calls, ['binance_global']);
      expect(sleeps, isEmpty);
    });
  });

  test('451 skips to the next candidate without waiting', () {
    fakeAsync((async) {
      final probe = ScriptedProbe({
        'binance_global': [ProbeOutcome.regionBlocked],
        'binance_vision': [ProbeOutcome.regionBlocked],
        'binance_us': [ProbeOutcome.ok],
      });
      final sleeps = <Duration>[];
      Resolution? result;
      build(
        probe,
        sleeps: sleeps,
        async: async,
      ).resolve().then((r) => result = r);
      async.flushMicrotasks();

      expect(result!.sourceId, 'binance_us');
      expect(result!.reason, ResolutionReason.regionBlocked);
      expect(sleeps, isEmpty);
      expect(probe.calls, ['binance_global', 'binance_vision', 'binance_us']);
    });
  });

  test('unavailable retries once after 5 s, then moves on', () {
    fakeAsync((async) {
      final probe = ScriptedProbe({
        'binance_global': [ProbeOutcome.unavailable, ProbeOutcome.unavailable],
        'binance_vision': [ProbeOutcome.unavailable, ProbeOutcome.ok],
      });
      final sleeps = <Duration>[];
      Resolution? result;
      build(
        probe,
        sleeps: sleeps,
        async: async,
      ).resolve().then((r) => result = r);
      async.flushMicrotasks();

      expect(result!.candidateId, 'binance_vision');
      expect(result!.reason, ResolutionReason.unavailable);
      expect(sleeps, [const Duration(seconds: 5), const Duration(seconds: 5)]);
      expect(probe.calls, [
        'binance_global',
        'binance_global',
        'binance_vision',
        'binance_vision',
      ]);
    });
  });

  test('everything blocked → CoinGecko with the region reason', () {
    fakeAsync((async) {
      final probe = ScriptedProbe({
        'binance_global': [ProbeOutcome.regionBlocked],
        'binance_vision': [ProbeOutcome.regionBlocked],
        'binance_us': [ProbeOutcome.unavailable],
      });
      final sleeps = <Duration>[];
      Resolution? result;
      build(
        probe,
        sleeps: sleeps,
        async: async,
      ).resolve().then((r) => result = r);
      async.flushMicrotasks();

      expect(result!.sourceId, 'coingecko');
      expect(result!.reason, ResolutionReason.regionBlocked);
      expect(result!.outcomes, {
        'binance_global': ProbeOutcome.regionBlocked,
        'binance_vision': ProbeOutcome.regionBlocked,
        'binance_us': ProbeOutcome.unavailable,
      });
    });
  });

  test('everything unavailable → CoinGecko with the unavailable reason', () {
    fakeAsync((async) {
      final probe = ScriptedProbe({
        'binance_global': [ProbeOutcome.unavailable],
        'binance_vision': [ProbeOutcome.unavailable],
        'binance_us': [ProbeOutcome.unavailable],
      });
      Resolution? result;
      build(probe, sleeps: [], async: async).resolve().then((r) => result = r);
      async.flushMicrotasks();

      expect(result!.sourceId, 'coingecko');
      expect(result!.reason, ResolutionReason.unavailable);
    });
  });

  test('fresh cache is returned without probing; force re-probes', () {
    fakeAsync((async) {
      final probe = ScriptedProbe({
        'binance_global': [ProbeOutcome.ok],
      });
      final cache = InMemoryResolutionCache();
      final resolver = build(probe, sleeps: [], async: async, cache: cache)
        ..resolve();
      async.flushMicrotasks();
      resolver.resolve();
      async.flushMicrotasks();
      expect(probe.calls, hasLength(1), reason: 'served from cache');

      resolver.resolve(force: true);
      async.flushMicrotasks();
      expect(probe.calls, hasLength(2));

      async.elapse(const Duration(hours: 25));
      resolver.resolve();
      async.flushMicrotasks();
      expect(probe.calls, hasLength(3), reason: 'ttl expired');
    });
  });

  test('default chain ends with CoinGecko and probes one miniTicker', () {
    final chain = defaultCandidates();
    expect(chain.map((c) => c.id), [
      'binance_global',
      'binance_vision',
      'binance_us',
    ]);
    expect(
      chain.first.wsProbe.toString(),
      'wss://stream.binance.com:9443/stream?streams=btcusdt%40miniTicker',
    );
    expect(
      chain.first.restPing.toString(),
      'https://api.binance.com/api/v3/ping',
    );
    expect(coinGeckoFallback.wsProbe, isNull);
  });
}
