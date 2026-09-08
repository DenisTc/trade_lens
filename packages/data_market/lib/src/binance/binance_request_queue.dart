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
/// - Every call declares its documented weight; when the used weight plus
///   the next call would cross [softLimit] the queue sleeps until the next
///   minute window.
/// - On 429 the queue waits `Retry-After` once and repeats the call.
/// - On 418 the queue records the ban and rejects all calls until it ends.
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
  DateTime? _bannedUntil;

  /// Used weight reported by the last response in the current minute.
  int get usedWeight => _usedWeight;

  DateTime? get bannedUntil => _bannedUntil;

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
    final now = _clock.now();
    final ban = _bannedUntil;
    if (ban != null) {
      if (now.isBefore(ban)) {
        throw BinanceRateLimitException(ban.difference(now), banned: true);
      }
      _bannedUntil = null;
    }
    await _waitForWindow(weight);

    try {
      return _record(await call());
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final retryAfter = _retryAfter(e.response);
      if (status == 418) {
        _bannedUntil = _clock.now().add(retryAfter);
        throw BinanceRateLimitException(retryAfter, banned: true);
      }
      if (status != 429) rethrow;
      await _sleep(retryAfter);
      try {
        return _record(await call());
      } on DioException catch (again) {
        if (again.response?.statusCode == 429 ||
            again.response?.statusCode == 418) {
          final wait = _retryAfter(again.response);
          if (again.response?.statusCode == 418) {
            _bannedUntil = _clock.now().add(wait);
          }
          throw BinanceRateLimitException(
            wait,
            banned: again.response?.statusCode == 418,
          );
        }
        rethrow;
      }
    }
  }

  Future<void> _waitForWindow(int weight) async {
    final now = _clock.now();
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
    _windowStart = _clock.now();
  }

  Response<T> _record<T>(Response<T> response) {
    final header = response.headers.value('x-mbx-used-weight-1m');
    final used = header == null ? null : int.tryParse(header);
    if (used != null) {
      _usedWeight = used;
      _windowStart = _clock.now();
    }
    return response;
  }

  static Duration _retryAfter(Response<Object?>? response) {
    final header = response?.headers.value('retry-after');
    final seconds = header == null ? null : int.tryParse(header);
    return Duration(seconds: seconds ?? 60);
  }

  static bool _sameMinute(DateTime a, DateTime b) =>
      a.toUtc().year == b.toUtc().year &&
      a.toUtc().month == b.toUtc().month &&
      a.toUtc().day == b.toUtc().day &&
      a.toUtc().hour == b.toUtc().hour &&
      a.toUtc().minute == b.toUtc().minute;
}
