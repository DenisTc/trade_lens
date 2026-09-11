/// TradeLens · Riverpod providers of the domain interfaces plus the few
/// widgets every feature needs (ADR-0003).
///
/// Providers here declare *what* features consume; the app decides *which*
/// implementation by overriding them in `ProviderScope`. Features never
/// import `data_market`, `ws_client` or any other implementation package.
library;

export 'l10n/generated/shared_localizations.dart';
export 'src/format.dart';
export 'src/l10n_ext.dart';
export 'src/providers/ai.dart';
export 'src/providers/assets.dart';
export 'src/providers/chart_overlays.dart';
export 'src/providers/config.dart';
export 'src/providers/connection.dart';
export 'src/providers/error_reporter.dart';
export 'src/providers/locale.dart';
export 'src/providers/market_data_source.dart';
export 'src/providers/pair.dart';
export 'src/providers/portfolio.dart';
export 'src/providers/quotes.dart';
export 'src/providers/retry.dart';
export 'src/providers/storage.dart';
export 'src/providers/theme.dart';
export 'src/theme/tokens.dart';
export 'src/widgets/async_value_view.dart';
export 'src/widgets/chips.dart';
export 'src/widgets/data_source_badge.dart';
export 'src/widgets/glass_tab_bar.dart';
export 'src/widgets/headers.dart';
export 'src/widgets/lens_ring.dart';
export 'src/widgets/skeleton.dart';
