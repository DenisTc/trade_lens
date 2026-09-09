import 'dart:async';

import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_shared/src/providers/market_data_source.dart';
import 'package:features_shared/src/providers/storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pair.g.dart';

/// Candle history plus live updates for one instrument and interval.
///
/// The local cache is shown first when it has this window, the REST
/// history replaces it as soon as it arrives and is written back to the
/// cache. With an empty cache the REST failure is the error; with a cache
/// the stale data stays on screen. Live candles (when the source streams
/// klines) are upserted into the same list; a stream error after the
/// history loaded keeps the data, the chart must not go blank.
@riverpod
class Candles extends _$Candles {
  @override
  Future<List<Candle>> build(Instrument instrument, Interval interval) async {
    final source = await ref.watch(marketDataSourceProvider.future);
    final cache = ref.watch(candleCacheProvider);
    final cached = await cache.read(instrument, interval);
    if (!ref.mounted) return cached;

    final fetch = source.klines(instrument, interval).then((result) {
      return switch (result) {
        Ok(:final value) => value,
        Err(:final error) => throw error,
      };
    });
    final List<Candle> history;
    if (cached.isEmpty) {
      history = await fetch;
    } else {
      // Serve the cache now; the network result replaces it when it lands.
      history = cached;
      unawaited(
        fetch.then(
          (fresh) {
            if (!ref.mounted) return;
            state = AsyncData(fresh);
            unawaited(
              cache
                  .write(instrument, interval, fresh)
                  .catchError((Object _) {}),
            );
          },
          onError: (Object _) {}, // keep the cached window on screen
        ),
      );
    }
    if (!ref.mounted) return history;
    if (cached.isEmpty) {
      unawaited(
        cache.write(instrument, interval, history).catchError((Object _) {}),
      );
    }
    // The screen may be gone or the interval switched while the REST call
    // was in flight; a subscription opened now would never be cancelled.
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
