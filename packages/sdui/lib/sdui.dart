/// TradeLens · server-driven UI: a JSON screen (schema 1, five node types)
/// parsed into a tree and rendered with widgets the host supplies for live
/// data and navigation. No Riverpod, no network: the host fetches the JSON
/// (Remote Config, an asset) and decides what to do with parse errors.
library;

export 'src/model.dart';
export 'src/parser.dart';
export 'src/renderer.dart';
export 'src/route_allowlist.dart';
