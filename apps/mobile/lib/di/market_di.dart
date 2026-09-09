import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:data_market/data_market.dart';
import 'package:domain/domain.dart';
import 'package:features_settings/features_settings.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
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

/// Region resolution survives restarts through the settings store
/// (spec: "результат кэшируется на 24 ч").
final class _SettingsResolutionCache implements ResolutionCache {
  _SettingsResolutionCache(this._store);

  final SettingsStore _store;

  @override
  Future<Resolution?> read() async {
    final raw = await _store.read(SettingsKeys.regionResolution);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      return Resolution(
        candidateId: json['candidateId']! as String,
        sourceId: json['sourceId']! as String,
        reason: ResolutionReason.values.byName(json['reason']! as String),
        at: DateTime.parse(json['at']! as String),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(Resolution resolution) => _store.write(
    SettingsKeys.regionResolution,
    jsonEncode({
      'candidateId': resolution.candidateId,
      'sourceId': resolution.sourceId,
      'reason': resolution.reason.name,
      'at': resolution.at.toUtc().toIso8601String(),
    }),
  );

  @override
  Future<void> clear() => _store.delete(SettingsKeys.regionResolution);
}

@Riverpod(keepAlive: true)
RegionResolver regionResolver(Ref ref) {
  final logger = ref.watch(appLoggerProvider);
  return RegionResolver(
    cache: _SettingsResolutionCache(ref.watch(settingsStoreProvider)),
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

/// Set by "Check source now": the next liveMarket build re-probes.
bool _forceNextResolve = false;

@Riverpod(keepAlive: true)
Future<LiveMarket> liveMarket(Ref ref) async {
  final logger = ref.watch(appLoggerProvider);
  final choice = await ref.watch(sourceChoiceSettingProvider.future);
  final Resolution resolution;
  if (choice == SourceChoice.auto) {
    final force = _forceNextResolve;
    _forceNextResolve = false;
    resolution = await ref.watch(regionResolverProvider).resolve(force: force);
  } else {
    // Manual choice (Settings, App Review): no probing, no cache.
    resolution = Resolution(
      candidateId: switch (choice) {
        SourceChoice.binance => 'binance_global',
        SourceChoice.binanceUs => 'binance_us',
        SourceChoice.coingecko || SourceChoice.auto => 'coingecko',
      },
      sourceId: choice.storageValue,
      reason: ResolutionReason.direct,
      at: DateTime.now().toUtc(),
    );
  }
  // The cache belongs to one source; entries of others are dropped now
  // (spec: "Кэш очищается при смене источника").
  final now = DateTime.now().toUtc();
  unawaited(
    ref
        .read(candleCacheProvider)
        .evict(
          maxAge: const Duration(hours: 24),
          now: now,
          keepSourceId: resolution.sourceId,
        )
        .catchError((Object _) {}),
  );
  unawaited(
    ref
        .read(lastQuoteStoreProvider)
        .evict(
          maxAge: const Duration(hours: 24),
          now: now,
          keepSourceId: resolution.sourceId,
        )
        .catchError((Object _) {}),
  );
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

/// "Check source now": re-probe the chain and rebuild the live stack.
@Riverpod(keepAlive: true)
void Function() recheckSource(Ref ref) => () {
  _forceNextResolve = true;
  ref.invalidate(liveMarketProvider);
};

/// Version and install attribution for the About screen.
Future<AboutInfo> _resolvedAboutInfo(Ref ref) async {
  final info = await PackageInfo.fromPlatform();
  final install = await ref
      .watch(settingsStoreProvider)
      .read(SettingsKeys.installAttribution);
  return AboutInfo.defaults().copyWith(
    version: '${info.version} (${info.buildNumber})',
    installSource: install,
  );
}

/// Overrides that bind the interface providers of `features_shared` to the
/// live stack. Tests pass their own overrides instead.
List<Override> marketOverrides() => [
  aboutInfoProvider.overrideWith(_resolvedAboutInfo),
  retryMarketSourceProvider.overrideWith(
    (ref) =>
        () => ref.invalidate(liveMarketProvider),
  ),
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
