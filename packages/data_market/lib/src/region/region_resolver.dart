import 'package:clock/clock.dart';
import 'package:core/core.dart';
import 'package:data_market/src/region/source_probe.dart';
import 'package:meta/meta.dart';

/// Why the resolver landed where it did. Drives the banner wording:
/// "Биржевые данные недоступны в вашем регионе" vs "Биржа не отвечает".
enum ResolutionReason { direct, regionBlocked, unavailable }

@immutable
final class Resolution {
  const Resolution({
    required this.candidateId,
    required this.sourceId,
    required this.reason,
    required this.at,
    this.outcomes = const {},
  });

  final String candidateId;
  final String sourceId;
  final ResolutionReason reason;
  final DateTime at;

  /// Everything that was probed, for the "О приложении" screen.
  final Map<String, ProbeOutcome> outcomes;

  bool isFresh(DateTime now, Duration ttl) => now.difference(at) < ttl;

  @override
  bool operator ==(Object other) =>
      other is Resolution &&
      other.candidateId == candidateId &&
      other.sourceId == sourceId &&
      other.reason == reason &&
      other.at == at;

  @override
  int get hashCode => Object.hash(candidateId, sourceId, reason, at);

  @override
  String toString() => 'Resolution($candidateId, $reason, $at)';
}

/// Where the last resolution lives between launches (settings table on
/// day 5). In-memory implementation for tests and the first wiring.
abstract interface class ResolutionCache {
  Future<Resolution?> read();
  Future<void> write(Resolution resolution);
  Future<void> clear();
}

final class InMemoryResolutionCache implements ResolutionCache {
  Resolution? _value;

  @override
  Future<Resolution?> read() async => _value;

  @override
  Future<void> write(Resolution resolution) async => _value = resolution;

  @override
  Future<void> clear() async => _value = null;
}

/// Walks the candidate chain and picks the first live source, falling back
/// to [fallback] (CoinGecko) when none answers.
///
/// - `regionBlocked` → next candidate immediately.
/// - `unavailable` → one retry after [retryDelay], then next candidate.
/// - The result is cached for [ttl]; [resolve] with `force` re-probes
///   (network change, "Проверить источник" button).
final class RegionResolver {
  RegionResolver({
    required this.probe,
    required this.candidates,
    required this.fallback,
    ResolutionCache? cache,
    Clock? clock,
    this.ttl = const Duration(hours: 24),
    this.retryDelay = const Duration(seconds: 5),
    this.logger = const NoopLogger(),
    Future<void> Function(Duration)? sleep,
  }) : cache = cache ?? InMemoryResolutionCache(),
       _clock = clock ?? const Clock(),
       _sleep = sleep ?? Future<void>.delayed;

  final SourceProbe probe;
  final List<SourceCandidate> candidates;

  /// REST-only last resort, never probed.
  final SourceCandidate fallback;
  final ResolutionCache cache;
  final Duration ttl;
  final Duration retryDelay;
  final Logger logger;
  final Clock _clock;
  final Future<void> Function(Duration) _sleep;

  Future<Resolution>? _inFlight;
  int _generation = 0;

  /// Concurrent plain calls share one probe run. A `force` call starts a
  /// new generation: an older run still in progress finishes but its
  /// result is not written to the cache, so a slow probe from the previous
  /// network cannot overwrite a fresher answer.
  Future<Resolution> resolve({bool force = false}) {
    if (!force) {
      final running = _inFlight;
      if (running != null) return running;
    }
    final generation = ++_generation;
    late final Future<Resolution> run;
    run = _resolve(force: force, generation: generation).whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
    });
    _inFlight = run;
    return run;
  }

  Future<Resolution> _resolve({
    required bool force,
    required int generation,
  }) async {
    if (!force) {
      final cached = await cache.read();
      if (cached != null && cached.isFresh(_clock.now(), ttl)) return cached;
    }

    final outcomes = <String, ProbeOutcome>{};
    var sawBlock = false;
    for (final candidate in candidates) {
      var outcome = await probe.probe(candidate);
      if (outcome == ProbeOutcome.unavailable) {
        logger.info('${candidate.id} unavailable, retrying in $retryDelay');
        await _sleep(retryDelay);
        outcome = await probe.probe(candidate);
      }
      outcomes[candidate.id] = outcome;
      switch (outcome) {
        case ProbeOutcome.ok:
          return await _commit(
            generation,
            Resolution(
              candidateId: candidate.id,
              sourceId: candidate.sourceId,
              reason: outcomes.length == 1
                  ? ResolutionReason.direct
                  : sawBlock
                  ? ResolutionReason.regionBlocked
                  : ResolutionReason.unavailable,
              at: _clock.now(),
              outcomes: Map.unmodifiable(outcomes),
            ),
          );
        case ProbeOutcome.regionBlocked:
          sawBlock = true;
        case ProbeOutcome.unavailable:
          break;
      }
    }
    return await _commit(
      generation,
      Resolution(
        candidateId: fallback.id,
        sourceId: fallback.sourceId,
        reason: sawBlock
            ? ResolutionReason.regionBlocked
            : ResolutionReason.unavailable,
        at: _clock.now(),
        outcomes: Map.unmodifiable(outcomes),
      ),
    );
  }

  Future<Resolution> _commit(int generation, Resolution resolution) async {
    if (generation != _generation) {
      logger.info('stale $resolution dropped (newer probe in flight)');
      return resolution;
    }
    logger.info('resolved $resolution');
    await cache.write(resolution);
    return resolution;
  }
}
