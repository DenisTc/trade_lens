/// TradeLens · Riverpod providers of the domain interfaces plus the few
/// widgets every feature needs (ADR-0003).
///
/// Providers here declare *what* features consume; the app decides *which*
/// implementation by overriding them in `ProviderScope`. Features never
/// import `data_market`, `ws_client` or any other implementation package.
library;

export 'src/providers/assets.dart';
export 'src/providers/connection.dart';
export 'src/providers/market_data_source.dart';
export 'src/providers/pair.dart';
export 'src/providers/quotes.dart';
export 'src/providers/retry.dart';
export 'src/widgets/async_value_view.dart';
export 'src/widgets/data_source_badge.dart';
