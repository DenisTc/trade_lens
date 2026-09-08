import 'package:features_shared/src/providers/market_data_source.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'retry.g.dart';

/// What the "Retry" button does when the source failed to initialise.
/// The default re-runs the interface provider; the app overrides it so the
/// whole live stack (resolver, socket) is rebuilt, not just the facade.
@Riverpod(keepAlive: true)
VoidCallback retryMarketSource(Ref ref) =>
    () => ref.invalidate(marketDataSourceProvider);
