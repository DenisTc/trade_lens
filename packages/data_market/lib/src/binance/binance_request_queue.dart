import 'dart:async';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';

/// Thrown when Binance asked us to stop: 418 (IP ban) or a 429 that
/// persisted after one wait. Carries how long to stay away.
final class BinanceRateLimitException implements Exception {
  const BinanceRateLimitException(this.retryAfter, {required this.banned});

  final Duration retryAfter;

  /// True for 418: the source refuses all requests until [retryAfter].
  final bool banned;

  @override
  String toString() =>
      'BinanceRateLimitException(${banned ? 'banned' : 'throttled'}, $retryAfter)';
}

/// Serialises REST calls and keeps them under Binance's per-minute weight
/// limit using the `x-mbx-used-weight-1m` response header.
///
/// - Every call declares its documented weight. It is added locally before
///   the request and replaced by the server's figure when a header comes
///   back, so the counter never lags behind reality.
/// - When the counter plus the next call would cross [softLimit] the queue
///   sleeps until the next UTC minute window.
/// - On 429 the queue waits `Retry-After` once and repeats the call. A
///   second 429 (or a 418) pauses the whole queue until the hint expires;
///   calls made meanwhile fail fast with [BinanceRateLimitException].
final class BinanceRequestQueue {
  BinanceRequestQueue({
    this.softLimit = 5000,
    Clock? clock,
    Future<void> Function(Duration)? sleep,
  }) : _clock = clock ?? const Clock(),
       _sleep = sleep ?? Future<void>.delayed;

  /// Below Binance's 6000/min so parallel apps on the same IP have headroom.
  final int softLimit;

  final Clock _clock;
  final Future<void> Function(Duration) _sleep;

  Future<void> _tail = Future.value();
  int _usedWeight = 0;
  DateTime? _windowStart;
  DateTime? _pausedUntil;
  bool _pauseIsBan = false;

  /// Weight consumed in the current minute (local estimate, corrected by
  /// the server header).
  int get usedWeight => _usedWeight;

  /// When the queue refuses requests because of a 429/418, until when.
  DateTime? get pausedUntil => _pausedUntil;

  /// True while the pause comes from a 418 IP ban rather than a 429.
  bool get isBanned => _pausedUntil != null && _pauseIsBan;

  Future<Response<T>> run<T>(int weight, Future<Response<T>> Function() call) {
    final completer = Completer<Response<T>>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await _execute(weight, call));
      } on Object catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<Response<T>> _execute<T>(
    int weight,
    Future<Response<T>> Function() call,
  ) async {
    _throwIfPaused();
    await _waitForWindow(weight);
    _usedWeight += weight;

    try {
      return _record(await call());
    } on DioException catch (e) {
      _recordHeaders(e.response);
      final status = e.response?.statusCode;
      if (status == 418) throw _pause(e.response, banned: true);
      if (status != 429) rethrow;

      await _sleep(_retryAfter(e.response));
      _usedWeight += weight;
      try {
        return _record(await call());
      } on DioException catch (again) {
        _recordHeaders(again.response);
        final s = again.response?.statusCode;
        if (s == 429 || s == 418) {
          throw _pause(again.response, banned: s == 418);
        }
        rethrow;
      }
    }
  }

  void _throwIfPaused() {
    final until = _pausedUntil;
    if (until == null) return;
    final now = _clock.now();
    if (now.isBefore(until)) {
      throw BinanceRateLimitException(
        until.difference(now),
        banned: _pauseIsBan,
      );
    }
    _pausedUntil = null;
    _pauseIsBan = false;
  }

  BinanceRateLimitException _pause(
    Response<Object?>? response, {
    required bool banned,
  }) {
    final wait = _retryAfter(response);
    _pausedUntil = _clock.now().add(wait);
    _pauseIsBan = banned;
    return BinanceRateLimitException(wait, banned: banned);
  }

  Future<void> _waitForWindow(int weight) async {
    final now = _clock.now().toUtc();
    final start = _windowStart;
    if (start == null || !_sameMinute(start, now)) {
      _usedWeight = 0;
      _windowStart = now;
      return;
    }
    if (_usedWeight + weight <= softLimit) return;
    final nextWindow = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    await _sleep(nextWindow.difference(now));
    _usedWeight = 0;
    _windowStart = _clock.now().toUtc();
  }

  Response<T> _record<T>(Response<T> response) {
    _recordHeaders(response);
    return response;
  }

  void _recordHeaders(Response<Object?>? response) {
    final header = response?.headers.value('x-mbx-used-weight-1m');
    final used = header == null ? null : int.tryParse(header);
    if (used != null) {
      _usedWeight = used;
      _windowStart = _clock.now().toUtc();
    }
  }

  static Duration _retryAfter(Response<Object?>? response) {
    final header = response?.headers.value('retry-after');
    final seconds = header == null ? null : int.tryParse(header);
    return Duration(seconds: seconds ?? 60);
  }

  static bool _sameMinute(DateTime a, DateTime b) {
    final x = a.toUtc();
    final y = b.toUtc();
    return x.year == y.year &&
        x.month == y.month &&
        x.day == y.day &&
        x.hour == y.hour &&
        x.minute == y.minute;
  }
}
