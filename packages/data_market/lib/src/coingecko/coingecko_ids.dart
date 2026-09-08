import 'package:domain/domain.dart';

/// CoinGecko coin ids for the default catalog. Kept next to the source
/// because it is CoinGecko's naming, not the asset's identity.
const coinGeckoIds = <String, String>{
  'btc': 'bitcoin',
  'eth': 'ethereum',
  'bnb': 'binancecoin',
  'sol': 'solana',
  'xrp': 'ripple',
  'ada': 'cardano',
  'doge': 'dogecoin',
  'trx': 'tron',
  'avax': 'avalanche-2',
  'link': 'chainlink',
  'dot': 'polkadot',
  'ltc': 'litecoin',
  'bch': 'bitcoin-cash',
  'uni': 'uniswap',
  'atom': 'cosmos',
  'xlm': 'stellar',
  'near': 'near',
  'apt': 'aptos',
  'arb': 'arbitrum',
  'fil': 'filecoin',
};

String? coinGeckoIdFor(Asset asset) => coinGeckoIds[asset.id];
