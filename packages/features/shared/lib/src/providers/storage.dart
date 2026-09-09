import 'package:domain/domain.dart';
import 'package:features_shared/src/providers/market_data_source.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'storage.g.dart';

/// Local storage contracts. The app overrides them with Drift-backed
/// implementations; tests use in-memory fakes.
@Riverpod(keepAlive: true, retry: noRetry)
PortfolioRepository portfolioRepository(Ref ref) =>
    throw UnimplementedError('override portfolioRepositoryProvider');

@Riverpod(keepAlive: true, retry: noRetry)
LastQuoteStore lastQuoteStore(Ref ref) =>
    throw UnimplementedError('override lastQuoteStoreProvider');

@Riverpod(keepAlive: true, retry: noRetry)
CandleCache candleCache(Ref ref) =>
    throw UnimplementedError('override candleCacheProvider');

@Riverpod(keepAlive: true, retry: noRetry)
SettingsStore settingsStore(Ref ref) =>
    throw UnimplementedError('override settingsStoreProvider');
