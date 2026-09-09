import 'package:ai_insights/ai_insights.dart';
import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// [MarketTools] over data the app already holds.
///
/// Two deliberate limits, both from the consent text: the model may ask
/// about the pair on screen and no other, and a tool call reads only
/// providers that are already loaded. Nothing here starts a request, so a
/// summary cannot quietly pull data the user did not open.
final class RiverpodMarketTools implements MarketTools {
  RiverpodMarketTools({
    required Ref ref,
    required MarketDataSource source,
    required Instrument instrument,
  }) : this._(ref, source, instrument);

  RiverpodMarketTools._(this._ref, this._source, this._instrument);

  final Ref _ref;
  final MarketDataSource _source;
  final Instrument _instrument;

  @override
  List<Instrument> get instruments => [_instrument];

  @override
  Set<Interval> get intervals => _source.capabilities.intervals;

  @override
  String get sourceName => _source.attribution;

  @override
  Future<List<Candle>> klines(
    Instrument instrument,
    Interval interval,
    int limit,
  ) async {
    if (instrument != _instrument) return const [];
    // `exists` before `read`: reading an interval the user never opened
    // would create the provider, and creating it fetches.
    final provider = candlesProvider(instrument, interval);
    if (!_ref.exists(provider)) return const [];
    final candles = _ref.read(provider).value;
    if (candles == null || candles.isEmpty) return const [];
    if (candles.length <= limit) return candles;
    return candles.sublist(candles.length - limit);
  }

  @override
  Future<OrderBookSnapshot?> orderBook(Instrument instrument) async {
    if (instrument != _instrument) return null;
    if (!_source.capabilities.orderBook) return null;
    final provider = orderBookProvider(instrument);
    if (!_ref.exists(provider)) return null;
    return _ref.read(provider).value;
  }
}
