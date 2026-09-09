import 'dart:async';

import 'package:core/core.dart';
import 'package:data_local/data_local.dart';
import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'storage_di.g.dart';

/// Cache lifetime promised in the privacy policy and the About screen.
const cacheMaxAge = Duration(hours: 24);

/// Seeds two demo positions into an empty portfolio for screenshots:
/// `--dart-define=TL_DEMO_PORTFOLIO=true`. Off in normal builds.
const demoPortfolio = bool.fromEnvironment('TL_DEMO_PORTFOLIO');

/// One database for the app's lifetime; closed with the container. Stale
/// cache rows are evicted on open so the 24 h promise holds even if the app
/// is never backgrounded.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = openAppDatabase();
  ref.onDispose(() => unawaited(db.close()));
  final now = DateTime.now().toUtc();
  unawaited(DriftCandleCache(db).evict(maxAge: cacheMaxAge, now: now));
  unawaited(DriftLastQuoteStore(db).evict(maxAge: cacheMaxAge, now: now));
  if (demoPortfolio) {
    unawaited(_seedDemoPortfolio(DriftPortfolioRepository(db)));
  }
  return db;
}

Future<void> _seedDemoPortfolio(PortfolioRepository repo) async {
  if ((await repo.positions()).isNotEmpty) return;
  final now = DateTime.now().toUtc();
  await repo.upsert(
    Position(
      id: 'demo-btc',
      asset: defaultAssets.first,
      quote: 'USDT',
      qty: Decimal.parse('0.5'),
      avgPrice: Decimal.parse('60000'),
      createdAt: now,
      note: 'cold wallet',
    ),
  );
  await repo.upsert(
    Position(
      id: 'demo-eth',
      asset: defaultAssets[1],
      quote: 'USDT',
      qty: Decimal.parse('4'),
      avgPrice: Decimal.parse('3100'),
      createdAt: now.add(const Duration(seconds: 1)),
    ),
  );
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
