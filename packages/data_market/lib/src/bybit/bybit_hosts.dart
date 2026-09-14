/// Bybit's public spot endpoints. One deployment only: unlike Binance,
/// Bybit has no regional mirror, so a block is a block.
abstract final class BybitHosts {
  static const sourceId = 'bybit';
  static const label = 'Bybit';
  static final Uri rest = Uri.parse('https://api.bybit.com/v5/');
  static final Uri ws = Uri.parse('wss://stream.bybit.com/v5/public/spot');
}
