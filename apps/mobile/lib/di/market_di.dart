import 'dart:async';

import 'package:core/core.dart';
import 'package:data_market/data_market.dart';
import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ws_client/ws_client.dart';

part 'market_di.g.dart';

/// Demo key shared by every install (spec, "Ключ CoinGecko"). Comes from
/// `--dart-define-from-file=env.json`; empty in CI and in the example file.
@Riverpod(keepAlive: true)
String coinGeckoDemoKey(Ref ref) =>
    const String.fromEnvironment('COINGECKO_DEMO_KEY');

/// The live market stack: the resolved source plus the socket behind it
/// (null for the REST-only fallback). Built once per app run.
typedef LiveMarket = ({
  MarketDataSource source,
  WsClient? ws,
  Resolution resolution,
});

@Riverpod(keepAlive: true)
Logger appLogger(Ref ref) =>
    kDebugMode ? const PrintLogger() : const NoopLogger();

@Riverpod(keepAlive: true)
RegionResolver regionResolver(Ref ref) {
  final logger = ref.watch(appLoggerProvider);
  return RegionResolver(
    probe: HttpSourceProbe(
      wsHandshake: ioWsHandshake,
      pins: tradeLensPins,
      logger: logger,
    ),
    candidates: defaultCandidates(),
    fallback: coinGeckoFallback,
    logger: logger,
  );
}

@Riverpod(keepAlive: true)
Future<LiveMarket> liveMarket(Ref ref) async {
  final logger = ref.watch(appLoggerProvider);
  final resolution = await ref.watch(regionResolverProvider).resolve();
  final hosts = switch (resolution.candidateId) {
    'binance_global' => BinanceHosts.global,
    'binance_vision' => BinanceHosts.vision,
    'binance_us' => BinanceHosts.us,
    _ => null,
  };
  if (hosts == null) {
    final source = CoinGeckoMarketDataSource(
      client: CoinGeckoRestClient(
        dio: createDio(baseUrl: CoinGeckoRestClient.baseUrl, logger: logger),
        demoKey: ref.watch(coinGeckoDemoKeyProvider),
      ),
    );
    return (source: source, ws: null, resolution: resolution);
  }
  final ws = WsClient(
    transport: const IoWsTransport(),
    url: hosts.ws,
    heartbeatStream: miniTickerStreamName('BTCUSDT'),
    logger: logger,
  );
  ref.onDispose(() => unawaited(ws.dispose()));
  final source = BinanceMarketDataSource(
    client: BinanceRestClient(
      dio: createDio(baseUrl: hosts.rest, pins: tradeLensPins, logger: logger),
    ),
    hosts: hosts,
    ws: ws,
    logger: logger,
  );
  return (source: source, ws: ws, resolution: resolution);
}

/// Overrides that bind the interface providers of `features_shared` to the
/// live stack. Tests pass their own overrides instead.
List<Override> marketOverrides() => [
  marketDataSourceProvider.overrideWith(
    (ref) async => (await ref.watch(liveMarketProvider.future)).source,
  ),
  connectionStatusProvider.overrideWith((ref) async* {
    final ws = (await ref.watch(liveMarketProvider.future)).ws;
    if (ws == null) {
      yield ConnectionStatus.idle;
      return;
    }
    yield ws.state.toDomain();
    yield* ws.states.map((s) => s.toDomain());
  }),
];

extension on WsConnectionState {
  ConnectionStatus toDomain() => switch (this) {
    WsConnectionState.idle => ConnectionStatus.idle,
    WsConnectionState.connecting => ConnectionStatus.connecting,
    WsConnectionState.connected => ConnectionStatus.connected,
    WsConnectionState.reconnecting => ConnectionStatus.reconnecting,
    WsConnectionState.suspended => ConnectionStatus.suspended,
  };
}
