import 'package:domain/src/market/asset.dart';

/// The 20 assets shown in the markets list. Order is display order.
/// Source-specific ids (CoinGecko slugs, Binance symbols) live in the
/// corresponding source, not here.
const defaultAssets = <Asset>[
  Asset(id: 'btc', symbol: 'BTC', name: 'Bitcoin'),
  Asset(id: 'eth', symbol: 'ETH', name: 'Ethereum'),
  Asset(id: 'bnb', symbol: 'BNB', name: 'BNB'),
  Asset(id: 'sol', symbol: 'SOL', name: 'Solana'),
  Asset(id: 'xrp', symbol: 'XRP', name: 'XRP'),
  Asset(id: 'ada', symbol: 'ADA', name: 'Cardano'),
  Asset(id: 'doge', symbol: 'DOGE', name: 'Dogecoin'),
  Asset(id: 'trx', symbol: 'TRX', name: 'TRON'),
  Asset(id: 'avax', symbol: 'AVAX', name: 'Avalanche'),
  Asset(id: 'link', symbol: 'LINK', name: 'Chainlink'),
  Asset(id: 'dot', symbol: 'DOT', name: 'Polkadot'),
  Asset(id: 'ltc', symbol: 'LTC', name: 'Litecoin'),
  Asset(id: 'bch', symbol: 'BCH', name: 'Bitcoin Cash'),
  Asset(id: 'uni', symbol: 'UNI', name: 'Uniswap'),
  Asset(id: 'atom', symbol: 'ATOM', name: 'Cosmos'),
  Asset(id: 'xlm', symbol: 'XLM', name: 'Stellar'),
  Asset(id: 'near', symbol: 'NEAR', name: 'NEAR Protocol'),
  Asset(id: 'apt', symbol: 'APT', name: 'Aptos'),
  Asset(id: 'arb', symbol: 'ARB', name: 'Arbitrum'),
  Asset(id: 'fil', symbol: 'FIL', name: 'Filecoin'),
];
