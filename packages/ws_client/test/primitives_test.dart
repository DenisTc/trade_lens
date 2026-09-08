// Tests drive futures with fakeAsync and pump them by hand.
// ignore_for_file: discarded_futures

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:ws_client/ws_client.dart';

import 'support/fake_transport.dart';

void main() {
  group('SubscriptionRegistry', () {
    test('counts listeners and reports first/last transitions', () {
      final registry = SubscriptionRegistry();
      expect(registry.add('a'), 1);
      expect(registry.add('a'), 2);
      expect(registry.add('b'), 1);
      expect(registry.wanted, {'a', 'b'});
      expect(registry.remove('a'), 1);
      expect(registry.remove('a'), 0);
      expect(registry.remove('a'), 0, reason: 'never negative');
      expect(registry.wanted, {'b'});
    });
  });

  group('OutboundLimiter', () {
    test('lets 4 messages through per rolling second', () {
      fakeAsync((async) {
        final limiter = OutboundLimiter();
        final granted = <Duration>[];
        for (var i = 0; i < 6; i++) {
          limiter.acquire().then((_) => granted.add(async.elapsed));
        }
        async.elapse(const Duration(seconds: 3));
        expect(granted, [
          Duration.zero,
          Duration.zero,
          Duration.zero,
          Duration.zero,
          const Duration(seconds: 1),
          const Duration(seconds: 1),
        ]);
      });
    });
  });

  group('Backoff', () {
    test('doubles from 1 s and caps at 30 s', () {
      final backoff = Backoff(random: NoJitter());
      expect(
        [for (var i = 0; i < 7; i++) backoff.next().inSeconds],
        [1, 2, 4, 8, 16, 30, 30],
      );
      backoff.reset();
      expect(backoff.next().inSeconds, 1);
    });

    test('applies ±20 % jitter', () {
      final delays = {for (var i = 0; i < 50; i++) Backoff().next()};
      expect(delays.length, greaterThan(1));
      for (final d in delays) {
        expect(d.inMilliseconds, inInclusiveRange(800, 1200));
      }
    });
  });

  group('coalesce', () {
    test('groups events within the window into one list', () {
      fakeAsync((async) {
        final source = StreamController<int>();
        final batches = <List<int>>[];
        coalesce(
          source.stream,
          const Duration(milliseconds: 16),
        ).listen(batches.add);

        source
          ..add(1)
          ..add(2);
        async.elapse(const Duration(milliseconds: 10));
        source.add(3);
        async.elapse(const Duration(milliseconds: 10));
        expect(batches, [
          [1, 2, 3],
        ]);

        source.add(4);
        async.elapse(const Duration(milliseconds: 20));
        expect(batches, [
          [1, 2, 3],
          [4],
        ]);

        source.close();
        async.flushMicrotasks();
      });
    });

    test('flushes the remainder on done', () {
      fakeAsync((async) {
        final source = StreamController<int>();
        final batches = <List<int>>[];
        var done = false;
        coalesce(
          source.stream,
          const Duration(seconds: 1),
        ).listen(batches.add, onDone: () => done = true);
        source
          ..add(1)
          ..close();
        async.flushMicrotasks();
        expect(batches, [
          [1],
        ]);
        expect(done, isTrue);
      });
    });
  });
}
