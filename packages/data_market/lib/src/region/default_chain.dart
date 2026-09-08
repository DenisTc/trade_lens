import 'package:data_market/src/binance/binance_hosts.dart';
import 'package:data_market/src/coingecko/coingecko_market_data_source.dart';
import 'package:data_market/src/coingecko/coingecko_rest_client.dart';
import 'package:data_market/src/region/source_probe.dart';

/// The chain from the spec: Binance Global → its market-data host →
/// Binance.US → CoinGecko. The probe subscribes to one liquid miniTicker.
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
];

final coinGeckoFallback = SourceCandidate(
  id: 'coingecko',
  sourceId: CoinGeckoMarketDataSource.sourceId,
  restPing: CoinGeckoRestClient.baseUrl.resolve('ping'),
);
