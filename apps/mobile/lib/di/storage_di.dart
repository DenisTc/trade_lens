import 'dart:async';

import 'package:data_local/data_local.dart';
import 'package:features_shared/features_shared.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'storage_di.g.dart';

/// One database for the app's lifetime; closed with the container.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = openAppDatabase();
  ref.onDispose(() => unawaited(db.close()));
  return db;
}

/// Binds the storage contracts of `features_shared` to Drift.
List<Override> storageOverrides() => [
  portfolioRepositoryProvider.overrideWith(
    (ref) => DriftPortfolioRepository(ref.watch(appDatabaseProvider)),
  ),
  lastQuoteStoreProvider.overrideWith(
    (ref) => DriftLastQuoteStore(ref.watch(appDatabaseProvider)),
  ),
  candleCacheProvider.overrideWith(
    (ref) => DriftCandleCache(ref.watch(appDatabaseProvider)),
  ),
  settingsStoreProvider.overrideWith(
    (ref) => DriftSettingsStore(ref.watch(appDatabaseProvider)),
  ),
];
