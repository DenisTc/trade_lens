// Tests drive futures with fakeAsync and pump them by hand, so awaiting
// would deadlock the fake clock.
// ignore_for_file: discarded_futures

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:data_market/data_market.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

Response<String> _ok({int usedWeight = 0}) => Response(
  requestOptions: RequestOptions(path: 'x'),
  statusCode: 200,
  data: 'ok',
  headers: Headers.fromMap({
    'x-mbx-used-weight-1m': ['$usedWeight'],
  }),
);

DioException _status(int code, {int retryAfter = 7}) => DioException(
  requestOptions: RequestOptions(path: 'x'),
  type: DioExceptionType.badResponse,
  response: Response(
    requestOptions: RequestOptions(path: 'x'),
    statusCode: code,
    headers: Headers.fromMap({
      'retry-after': ['$retryAfter'],
    }),
  ),
);

void main() {
  final start = DateTime.utc(2026, 9, 8, 12, 0, 30);

  test('serialises calls in order', () {
    fakeAsync((async) {
      final queue = BinanceRequestQueue();
      final order = <int>[];
      Future<Response<String>> call(int n) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        order.add(n);
        return _ok();
      }

      queue
        ..run(1, () => call(1))
        ..run(1, () => call(2))
        ..run(1, () => call(3));
      async.elapse(const Duration(seconds: 1));
      expect(order, [1, 2, 3]);
    });
  });

  test('tracks used weight from the response header', () {
    fakeAsync((async) {
      final queue = BinanceRequestQueue()
        ..run(2, () async => _ok(usedWeight: 42));
      async.flushMicrotasks();
      expect(queue.usedWeight, 42);
    });
  });

  test('waits for the next minute when the soft limit would be crossed', () {
    fakeAsync((async) {
      final sleeps = <Duration>[];
      final queue = BinanceRequestQueue(
        softLimit: 100,
        clock: Clock(() => start.add(async.elapsed)),
        sleep: (d) async {
          sleeps.add(d);
          async.elapse(d);
        },
      )..run(1, () async => _ok(usedWeight: 99));
      async.flushMicrotasks();

      var ran = false;
      queue.run(5, () async {
        ran = true;
        return _ok(usedWeight: 5);
      });
      async.flushMicrotasks();

      expect(sleeps, [const Duration(seconds: 30)]);
      expect(ran, isTrue);
      expect(queue.usedWeight, 5);
    });
  });

  test('429: sleeps Retry-After once and repeats the call', () {
    fakeAsync((async) {
      final sleeps = <Duration>[];
      final queue = BinanceRequestQueue(sleep: (d) async => sleeps.add(d));
      var calls = 0;
      Object? result;
      queue
          .run(1, () async {
            calls++;
            if (calls == 1) throw _status(429);
            return _ok();
          })
          .then((r) => result = r.data);
      async.flushMicrotasks();

      expect(calls, 2);
      expect(sleeps, [const Duration(seconds: 7)]);
      expect(result, 'ok');
    });
  });

  test('418: records the ban and rejects until it expires', () {
    fakeAsync((async) {
      final queue = BinanceRequestQueue(
        clock: Clock(() => start.add(async.elapsed)),
      );
      Object? first;
      queue
          .run<String>(1, () async => throw _status(418, retryAfter: 120))
          .catchError((Object e) {
            first = e;
            return _ok();
          });
      async.flushMicrotasks();
      expect(
        first,
        isA<BinanceRateLimitException>().having(
          (e) => e.banned,
          'banned',
          isTrue,
        ),
      );
      expect(queue.pausedUntil, start.add(const Duration(seconds: 120)));
      expect(queue.isBanned, isTrue);

      var called = false;
      Object? second;
      queue
          .run(1, () async {
            called = true;
            return _ok();
          })
          .catchError((Object e) {
            second = e;
            return _ok();
          });
      async.flushMicrotasks();
      expect(called, isFalse, reason: 'no requests during a ban');
      expect(
        second,
        isA<BinanceRateLimitException>().having(
          (e) => e.retryAfter,
          'retryAfter',
          const Duration(seconds: 120),
        ),
      );

      async.elapse(const Duration(seconds: 121));
      var calledAfter = false;
      queue.run(1, () async {
        calledAfter = true;
        return _ok();
      });
      async.flushMicrotasks();
      expect(calledAfter, isTrue);
    });
  });

  test('a second 429 pauses the queue for Retry-After', () {
    fakeAsync((async) {
      final sleeps = <Duration>[];
      final queue = BinanceRequestQueue(
        clock: Clock(() => start.add(async.elapsed)),
        sleep: (d) async => sleeps.add(d),
      );
      Object? first;
      queue
          .run<String>(1, () async => throw _status(429, retryAfter: 9))
          .catchError((Object e) {
            first = e;
            return _ok();
          });
      async.flushMicrotasks();
      expect(sleeps, [const Duration(seconds: 9)], reason: 'one wait');
      expect(
        first,
        isA<BinanceRateLimitException>().having(
          (e) => e.banned,
          'banned',
          isFalse,
        ),
      );

      var called = false;
      Object? second;
      queue
          .run<String>(1, () async {
            called = true;
            return _ok();
          })
          .catchError((Object e) {
            second = e;
            return _ok();
          });
      async.flushMicrotasks();
      expect(called, isFalse, reason: 'queue paused until Retry-After');
      expect(second, isA<BinanceRateLimitException>());
      expect(queue.isBanned, isFalse);

      async.elapse(const Duration(seconds: 10));
      var resumed = false;
      queue.run<String>(1, () async {
        resumed = true;
        return _ok();
      });
      async.flushMicrotasks();
      expect(resumed, isTrue);
    });
  });

  test('minute window is computed in UTC even for a local clock', () {
    fakeAsync((async) {
      final local = DateTime(2026, 9, 8, 12, 0, 30); // local time zone
      final sleeps = <Duration>[];
      final queue = BinanceRequestQueue(
        softLimit: 100,
        clock: Clock(() => local.add(async.elapsed)),
        sleep: (d) async {
          sleeps.add(d);
          async.elapse(d);
        },
      )..run(1, () async => _ok(usedWeight: 99));
      async.flushMicrotasks();
      queue.run(5, () async => _ok(usedWeight: 5));
      async.flushMicrotasks();
      expect(sleeps, [const Duration(seconds: 30)]);
    });
  });

  test('declared weight accumulates locally without a server header', () {
    fakeAsync((async) {
      final queue = BinanceRequestQueue()
        ..run(
          2,
          () async => Response(
            requestOptions: RequestOptions(path: 'x'),
            statusCode: 200,
            data: 'ok',
          ),
        )
        ..run(
          3,
          () async => Response(
            requestOptions: RequestOptions(path: 'x'),
            statusCode: 200,
            data: 'ok',
          ),
        );
      async.flushMicrotasks();
      expect(queue.usedWeight, 5);
    });
  });

  test('non rate-limit errors pass through unchanged', () {
    fakeAsync((async) {
      final queue = BinanceRequestQueue();
      Object? error;
      queue.run<String>(1, () async => throw _status(451)).catchError((
        Object e,
      ) {
        error = e;
        return _ok();
      });
      async.flushMicrotasks();
      expect(
        error,
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          451,
        ),
      );
    });
  });
}
