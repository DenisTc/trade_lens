import 'package:domain/domain.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'market_data_source.g.dart';

/// Retry policy that never retries; the caller decides what to do.
Duration? noRetry(int retryCount, Object error) => null;

/// The active source after region resolution (or manual choice).
///
/// Declared here without an implementation; the app overrides it with the
/// resolver-backed provider (`marketDataSourceProvider.overrideWith`).
/// Async on purpose: resolving the region takes a network round-trip.
///
/// Riverpod 3 retries failed providers with a backoff by default. That is
/// switched off here: the region resolver already retries and falls back,
/// and a failure past that point must surface as an error state with a
/// retry button, not as a loader that spins for seconds.
@Riverpod(keepAlive: true, retry: noRetry)
Future<MarketDataSource> marketDataSource(Ref ref) {
  throw UnimplementedError(
    'marketDataSourceProvider must be overridden by the app',
  );
}
