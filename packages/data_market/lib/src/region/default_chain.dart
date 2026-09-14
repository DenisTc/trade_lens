import 'package:data_market/src/binance/binance_hosts.dart';
import 'package:data_market/src/bybit/bybit_hosts.dart';
import 'package:data_market/src/bybit/bybit_rest_client.dart';
import 'package:data_market/src/bybit/bybit_ws_protocol.dart';
import 'package:data_market/src/coingecko/coingecko_market_data_source.dart';
import 'package:data_market/src/coingecko/coingecko_rest_client.dart';
import 'package:data_market/src/region/source_probe.dart';

/// The chain from the spec, plus Bybit: Binance Global → its market-data
/// host → Binance.US → Bybit → CoinGecko. An exchange with a socket beats
/// the REST-only fallback, and Bybit answers where Binance is blocked.
/// The probe subscribes to one liquid ticker.
List<SourceCandidate> defaultCandidates({String probeSymbol = 'BTCUSDT'}) => [
  SourceCandidate(
    id: 'binance_global',
    sourceId: BinanceHosts.global.sourceId,
    restPing: BinanceHosts.global.rest.resolve('ping'),
    wsProbe: BinanceHosts.global.wsProbe(probeSymbol),
  ),
  SourceCandidate(
    id: 'binance_vision',
    sourceId: BinanceHosts.vision.sourceId,
    restPing: BinanceHosts.vision.rest.resolve('ping'),
    wsProbe: BinanceHosts.vision.wsProbe(probeSymbol),
  ),
  SourceCandidate(
    id: 'binance_us',
    sourceId: BinanceHosts.us.sourceId,
    restPing: BinanceHosts.us.rest.resolve('ping'),
    wsProbe: BinanceHosts.us.wsProbe(probeSymbol),
  ),
  SourceCandidate(
    id: 'bybit',
    sourceId: BybitHosts.sourceId,
    restPing: BybitRestClient.ping(BybitHosts.rest),
    wsProbe: BybitHosts.ws,
    wsProbeCommand: const BybitWsProtocol().subscribe([
      bybitTickerTopic(probeSymbol),
    ], 1),
  ),
];

final coinGeckoFallback = SourceCandidate(
  id: 'coingecko',
  sourceId: CoinGeckoMarketDataSource.sourceId,
  restPing: CoinGeckoRestClient.baseUrl.resolve('ping'),
);
