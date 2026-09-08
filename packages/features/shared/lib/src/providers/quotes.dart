import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_shared/src/providers/market_data_source.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'quotes.g.dart';

/// Live quote of one instrument. Family by [Instrument] (value equality):
/// the pair screen and the portfolio watching the same pair share one
/// provider, and the exchange subscription stays open until the *last*
/// consumer is gone, because the provider is autoDispose and the socket
/// registry counts listeners, not screens.
@riverpod
Stream<Quote> quote(Ref ref, Instrument instrument) async* {
  final source = await ref.watch(marketDataSourceProvider.future);
  yield* source.quoteStream([instrument]);
}

/// Last [QuoteHistory.capacity] prices of an instrument for the sparkline.
@riverpod
class QuoteHistory extends _$QuoteHistory {
  static const capacity = 60;

  @override
  List<Decimal> build(Instrument instrument) {
    ref.listen(quoteProvider(instrument), (_, next) {
      final quote = next.value;
      if (quote == null) return;
      final history = state.length >= capacity
          ? state.sublist(state.length - capacity + 1)
          : state;
      state = [...history, quote.price];
    });
    return const [];
  }
}
