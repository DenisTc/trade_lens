import 'dart:async';

import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_shared/src/providers/market_data_source.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pair.g.dart';

/// Candle history plus live updates for one instrument and interval.
///
/// Loads up to 500 candles over REST, then (when the source streams
/// klines) upserts every live candle into the same list. A stream error
/// after the history loaded keeps the data on screen: the connection dot
/// tells the story, the chart must not go blank (spec, "Сценарии").
@riverpod
class Candles extends _$Candles {
  @override
  Future<List<Candle>> build(Instrument instrument, Interval interval) async {
    final source = await ref.watch(marketDataSourceProvider.future);
    final history = switch (await source.klines(instrument, interval)) {
      Ok(:final value) => value,
      Err(:final error) => throw error,
    };
    // The screen may be gone or the interval switched while the REST call
    // was in flight; a subscription opened now would never be cancelled.
    if (!ref.mounted) return history;
    if (source.capabilities.klineStream && interval.duration != null) {
      final subscription = source
          .klineStream(instrument, interval)
          .listen(_upsert, onError: (Object _) {});
      ref.onDispose(subscription.cancel);
    }
    return history;
  }

  void _upsert(Candle candle) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.upsert(candle));
  }
}

/// The interval the pair screen shows. Defaults to the first one the active
/// source supports (`auto` for the REST fallback).
@riverpod
class SelectedInterval extends _$SelectedInterval {
  @override
  Interval build() {
    final source = ref.watch(marketDataSourceProvider).value;
    final intervals =
        source?.capabilities.intervals ?? Capabilities.full.intervals;
    return intervals.contains(Interval.h1) ? Interval.h1 : intervals.first;
  }

  Interval get value => state;

  set value(Interval interval) => state = interval;
}

/// Full top-10 book; each event replaces the previous one.
@riverpod
Stream<OrderBookSnapshot> orderBook(Ref ref, Instrument instrument) async* {
  final source = await ref.watch(marketDataSourceProvider.future);
  yield* source.orderBookStream(instrument);
}

/// Last [recentTradesLimit] trades, newest first.
const recentTradesLimit = 30;

@riverpod
Stream<List<Trade>> recentTrades(Ref ref, Instrument instrument) async* {
  final source = await ref.watch(marketDataSourceProvider.future);
  var trades = <Trade>[];
  await for (final trade in source.tradeStream(instrument)) {
    trades = [trade, ...trades.take(recentTradesLimit - 1)];
    yield trades;
  }
}
