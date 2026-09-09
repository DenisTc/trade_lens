import 'dart:async';

import 'package:clock/clock.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_shared/src/providers/market_data_source.dart';
import 'package:features_shared/src/providers/storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'quotes.g.dart';

/// How often a live quote is written to `last_quotes` per instrument.
/// One tick a second times twenty rows must not become twenty writes a
/// second.
const quotePersistInterval = Duration(seconds: 15);

/// Live quote of one instrument. Family by [Instrument] (value equality):
/// the pair screen and the portfolio watching the same pair share one
/// provider, and the exchange subscription stays open until the *last*
/// consumer is gone, because the provider is autoDispose and the socket
/// registry counts listeners, not screens.
@riverpod
Stream<Quote> quote(Ref ref, Instrument instrument) async* {
  final source = await ref.watch(marketDataSourceProvider.future);
  final store = ref.watch(lastQuoteStoreProvider);
  DateTime? lastSaved;
  // `yield*` (not `await for`) so cancelling the provider cancels the
  // exchange subscription immediately, without waiting for the next tick.
  yield* source.quoteStream([instrument]).map((quote) {
    final now = clock.now();
    final saved = lastSaved;
    if (saved == null || now.difference(saved) >= quotePersistInterval) {
      lastSaved = now;
      unawaited(store.save(quote).catchError((Object _) {}));
    }
    return quote;
  });
}

/// Last [QuoteHistory.capacity] prices of an instrument for the sparkline.
@riverpod
class QuoteHistory extends _$QuoteHistory {
  static const capacity = 60;

  @override
  List<Decimal> build(Instrument instrument) {
    ref.listen(quoteProvider(instrument), (_, next) {
      // Loading/error states can carry the previous value; only a fresh
      // AsyncData is a tick.
      if (next case AsyncData(value: final quote)) _append(quote);
    });
    return const [];
  }

  void _append(Quote quote) {
    final history = state.length >= capacity
        ? state.sublist(state.length - capacity + 1)
        : state;
    state = [...history, quote.price];
  }
}
