import 'package:domain/domain.dart';
import 'package:features_shared/src/providers/config.dart';
import 'package:features_shared/src/providers/error_reporter.dart';
import 'package:features_shared/src/providers/market_data_source.dart';
import 'package:features_shared/src/providers/quotes.dart';
import 'package:features_shared/src/providers/storage.dart';
import 'package:features_shared/src/testing/fake_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

/// Overrides that bind every interface provider to a fake, for widget and
/// provider tests. Pass your own fakes to inspect them.
List<Override> fakeOverrides({
  required MarketDataSource source,

  /// Replaces `source` when set, e.g. to simulate a failing resolver.
  Future<MarketDataSource> Function()? sourceFactory,
  PortfolioRepository? portfolio,
  LastQuoteStore? lastQuotes,
  CandleCache? candleCache,
  SettingsStore? settings,
  InsightsConfigSource? config,
  ErrorReporter? errorReporter,

  /// Keep-alive grace of quote providers; zero by default so disposal is
  /// observable right away.
  Duration quoteKeepAlive = Duration.zero,
}) => [
  marketDataSourceProvider.overrideWith(
    (ref) => sourceFactory?.call() ?? Future.value(source),
  ),
  portfolioRepositoryProvider.overrideWithValue(
    portfolio ?? FakePortfolioRepository(),
  ),
  lastQuoteStoreProvider.overrideWithValue(lastQuotes ?? FakeLastQuoteStore()),
  candleCacheProvider.overrideWithValue(candleCache ?? FakeCandleCache()),
  settingsStoreProvider.overrideWithValue(settings ?? FakeSettingsStore()),
  insightsConfigSourceProvider.overrideWithValue(
    config ?? FakeInsightsConfigSource(),
  ),
  if (errorReporter != null)
    errorReporterProvider.overrideWithValue(errorReporter),
  // No keep-alive grace in tests: disposal is observable right away.
  quoteKeepAliveProvider.overrideWithValue(quoteKeepAlive),
];
