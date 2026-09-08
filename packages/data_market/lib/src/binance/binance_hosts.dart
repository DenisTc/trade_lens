/// REST and WebSocket endpoints of one Binance deployment.
///
/// `vision` is the market-data-only host pair documented by Binance
/// (`data-api.binance.vision`, `data-stream.binance.vision`); it serves the
/// same public endpoints as `api.binance.com` and is tried right after it.
final class BinanceHosts {
  const BinanceHosts({
    required this.sourceId,
    required this.rest,
    required this.ws,
    required this.label,
  });

  static final global = BinanceHosts(
    sourceId: 'binance',
    label: 'Binance',
    rest: Uri.parse('https://api.binance.com/api/v3/'),
    ws: Uri.parse('wss://stream.binance.com:9443/stream'),
  );

  static final vision = BinanceHosts(
    sourceId: 'binance',
    label: 'Binance (market data host)',
    rest: Uri.parse('https://data-api.binance.vision/api/v3/'),
    ws: Uri.parse('wss://data-stream.binance.vision/stream'),
  );

  static final us = BinanceHosts(
    sourceId: 'binance_us',
    label: 'Binance.US',
    rest: Uri.parse('https://api.binance.us/api/v3/'),
    ws: Uri.parse('wss://stream.binance.us:9443/stream'),
  );

  /// `binance` for Global and the vision hosts, `binance_us` for Binance.US.
  final String sourceId;
  final String label;
  final Uri rest;
  final Uri ws;

  /// The miniTicker stream used by the region probe and as heartbeat.
  Uri wsProbe(String symbol) => ws.replace(
    queryParameters: {'streams': '${symbol.toLowerCase()}@miniTicker'},
  );
}
