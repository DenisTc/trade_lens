import 'package:domain/domain.dart';
import 'package:features_shared/src/providers/market_data_source.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'assets.g.dart';

/// The catalog shown in the markets list. Overridable for tests and for a
/// future Remote Config-driven list.
@Riverpod(keepAlive: true)
List<Asset> assets(Ref ref) => defaultAssets;

/// Instruments of the active source for the catalog, in catalog order.
/// Assets the source does not list (Binance.US) are simply absent.
@riverpod
Future<List<Instrument>> marketInstruments(Ref ref) async {
  final source = await ref.watch(marketDataSourceProvider.future);
  return source.instruments(ref.watch(assetsProvider), source.defaultQuote);
}
