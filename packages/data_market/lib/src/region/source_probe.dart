/// What a probe learned about one candidate.
enum ProbeOutcome {
  /// REST answered 200 and the WebSocket handshake delivered data.
  ok,

  /// HTTP 451: confirmed regional block. Move on without retrying.
  regionBlocked,

  /// Timeout, 5xx, network error or a dead WebSocket. Retry once, then
  /// move on. Bad Wi-Fi must not look like a geo-block.
  unavailable,
}

/// One entry of the fallback chain. Several candidates may map to the same
/// [sourceId] (Binance Global and its market-data host).
final class SourceCandidate {
  const SourceCandidate({
    required this.id,
    required this.sourceId,
    required this.restPing,
    this.wsProbe,
  });

  /// Unique within the chain: `binance_global`, `binance_vision`, ...
  final String id;

  /// The `MarketDataSource.id` this candidate serves.
  final String sourceId;

  /// Full URL that must answer 200, e.g. `.../api/v3/ping`.
  final Uri restPing;

  /// Combined-stream URL with one miniTicker subscription. Null for
  /// REST-only sources.
  final Uri? wsProbe;
}

abstract interface class SourceProbe {
  Future<ProbeOutcome> probe(SourceCandidate candidate);
}
