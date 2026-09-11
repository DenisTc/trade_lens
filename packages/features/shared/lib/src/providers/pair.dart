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
  /// Bumped per build so a REST reply of a superseded build is ignored.
  int _generation = 0;

  /// Live candles received while the REST history is still in flight;
  /// applied on top of it so a late reply cannot roll them back.
  List<Candle> _liveWhileLoading = const [];

  /// The network replacement of a cached window, while it is in flight.
  /// Paging waits for it: a cursor taken from the cache could otherwise
  /// leave a hole between the page and the refreshed window.
  Future<void>? _refresh;

  @override
  Future<List<Candle>> build(Instrument instrument, Interval interval) async {
    final generation = ++_generation;
    _liveWhileLoading = const [];
    _refresh = null;
    _pagingGeneration = null;
    _historyExhausted = false;
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
      _refresh = fetch.then(
        (fresh) {
          if (!ref.mounted || generation != _generation) return;
          final merged = _liveWhileLoading.fold(fresh, (l, c) => l.upsert(c));
          _liveWhileLoading = const [];
          state = AsyncData(merged);
          unawaited(
            cache.write(instrument, interval, fresh).catchError((Object _) {}),
          );
        },
        onError: (Object _) {}, // keep the cached window on screen
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
    _liveWhileLoading = [..._liveWhileLoading, candle];
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.upsert(candle));
  }

  /// The build a page is in flight for; null when none is.
  int? _pagingGeneration;
  bool _historyExhausted = false;

  /// Candles kept in memory per pair and interval. Ten pages: enough to
  /// scroll back a week of minutes, small enough that a live tick — which
  /// copies the list — and the overlays stay cheap.
  static const maxCandles = 5000;

  /// Prepends the page before the oldest candle on screen. One page at a
  /// time; a page with nothing older in it ends the paging for this
  /// build, and a failure is silent — what is on screen stays.
  Future<void> loadOlder() async {
    final generation = _generation;
    if (_pagingGeneration != null || _historyExhausted) return;
    final source = ref.read(marketDataSourceProvider).value;
    if (source == null || !source.capabilities.history) return;
    _pagingGeneration = generation;
    try {
      // A cached window is about to be replaced: page from the fresh
      // one, or the page and the window would not meet.
      await _refresh;
      if (!ref.mounted || generation != _generation) return;
      final current = state.value;
      if (current == null || current.isEmpty) return;
      if (current.length >= maxCandles) {
        _historyExhausted = true;
        return;
      }
      final oldest = current.first.openTime;
      final result = await source.klines(instrument, interval, before: oldest);
      if (!ref.mounted || generation != _generation) return;
      if (result case Ok(:final value)) {
        final older = [
          for (final c in value)
            if (c.openTime.isBefore(oldest)) c,
        ];
        if (older.isEmpty) {
          _historyExhausted = true;
          return;
        }
        // Live candles may have landed meanwhile: they are in the state,
        // not in `current`, and the page is merged rather than glued on.
        state = AsyncData(
          older.fold(state.value ?? current, (l, c) => l.upsert(c)),
        );
      }
    } finally {
      if (_pagingGeneration == generation) _pagingGeneration = null;
    }
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
