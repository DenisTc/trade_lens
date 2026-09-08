// Tests drive futures with fakeAsync and pump them by hand.
// ignore_for_file: discarded_futures

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:ws_client/testing.dart';
import 'package:ws_client/ws_client.dart';

void main() {
  final url = Uri.parse('wss://stream.test/stream');
  const heartbeat = 'btcusdt@miniTicker';

  WsClient build(
    FakeTransport transport, {
    String? heartbeatStream = heartbeat,
  }) => WsClient(
    transport: transport,
    url: url,
    heartbeatStream: heartbeatStream,
    backoff: Backoff(random: NoJitter()),
  );

  List<String> paramsOf(Map<String, Object?> command) =>
      (command['params']! as List).cast<String>();

  test('first listener opens the socket and batches subscriptions into one command', () {
    fakeAsync((async) {
      final transport = FakeTransport();
      final client = build(transport);
      final states = <WsConnectionState>[];
      client.states.listen(states.add);

      client.subscribe('ethusdt@trade').listen((_) {});
      async.elapse(const Duration(milliseconds: 100));
      client.subscribe('ethusdt@miniTicker').listen((_) {});
      async.elapse(const Duration(milliseconds: 300));

      expect(transport.attempts, [url]);
      final commands = transport.last.commands;
      expect(commands, hasLength(1));
      expect(commands.single['method'], 'SUBSCRIBE');
      expect(paramsOf(commands.single), [
        heartbeat,
        'ethusdt@miniTicker',
        'ethusdt@trade',
      ]);
      expect(states, [
        WsConnectionState.connecting,
        WsConnectionState.connected,
      ]);
      expect(client.serverSubscriptions, {
        heartbeat,
        'ethusdt@miniTicker',
        'ethusdt@trade',
      });
    });
  });

  test('a second listener of the same stream sends nothing', () {
    fakeAsync((async) {
      final transport = FakeTransport();
      final client = build(transport);
      client.subscribe('ethusdt@trade').listen((_) {});
      async.elapse(const Duration(seconds: 1));
      client.subscribe('ethusdt@trade').listen((_) {});
      async.elapse(const Duration(seconds: 1));

      expect(client.listenerCount('ethusdt@trade'), 2);
      expect(transport.last.commands, hasLength(1));
    });
  });

  test('last listener leaving unsubscribes after 2 s; re-listening within the delay cancels it', () {
    fakeAsync((async) {
      final transport = FakeTransport();
      final client = build(transport);
      final a = client.subscribe('ethusdt@trade').listen((_) {});
      final b = client.subscribe('ethusdt@trade').listen((_) {});
      async.elapse(const Duration(seconds: 1));

      a.cancel();
      async.elapse(const Duration(seconds: 3));
      expect(
        transport.last.commands,
        hasLength(1),
        reason: 'one listener remains',
      );

      b.cancel();
      async.elapse(const Duration(seconds: 1));
      expect(
        transport.last.commands,
        hasLength(1),
        reason: 'still inside the 2 s grace',
      );
      client.subscribe('ethusdt@trade').listen((_) {});
      async.elapse(const Duration(seconds: 3));
      expect(
        transport.last.commands,
        hasLength(1),
        reason: 're-listen cancelled the unsubscribe',
      );
    });
  });

  test(
    'UNSUBSCRIBE is sent 2 s after the last listener leaves, heartbeat stays',
    () {
      fakeAsync((async) {
        final transport = FakeTransport();
        final client = build(transport);
        final trade = client.subscribe('ethusdt@trade').listen((_) {});
        client.subscribe('ethusdt@miniTicker').listen((_) {});
        async.elapse(const Duration(seconds: 1));

        trade.cancel();
        async.elapse(const Duration(seconds: 3));

        final commands = transport.last.commands;
        expect(commands, hasLength(2));
        expect(commands.last['method'], 'UNSUBSCRIBE');
        expect(paramsOf(commands.last), ['ethusdt@trade']);
        expect(client.serverSubscriptions, {heartbeat, 'ethusdt@miniTicker'});
      });
    },
  );

  test('socket closes when nothing is wanted any more', () {
    fakeAsync((async) {
      final transport = FakeTransport();
      final client = build(transport);
      final sub = client.subscribe('ethusdt@trade').listen((_) {});
      async.elapse(const Duration(seconds: 1));
      sub.cancel();
      // 2 s unsubscribe grace + 250 ms batch window.
      async.elapse(const Duration(seconds: 3));

      expect(transport.last.closed, isTrue);
      expect(client.state, WsConnectionState.idle);
    });
  });

  test(
    'frames are dispatched by stream name; acknowledgements are ignored',
    () {
      fakeAsync((async) {
        final transport = FakeTransport();
        final client = build(transport);
        final trades = <WsMessage>[];
        final tickers = <WsMessage>[];
        client.subscribe('ethusdt@trade').listen(trades.add);
        client.subscribe('ethusdt@miniTicker').listen(tickers.add);
        async.elapse(const Duration(seconds: 1));

        transport.last
          ..push({'result': null, 'id': 1})
          ..push({
            'stream': 'ethusdt@trade',
            'data': {'p': '1'},
          })
          ..push({
            'stream': 'ethusdt@miniTicker',
            'data': {'c': '2'},
          })
          ..push({'stream': 'nobody@trade', 'data': <String, Object?>{}})
          ..pushRaw('not json');
        async.flushMicrotasks();

        expect(trades.map((m) => m.data), [
          {'p': '1'},
        ]);
        expect(tickers.map((m) => m.data), [
          {'c': '2'},
        ]);
      });
    },
  );

  test('drop → reconnect at 1, 2, 4 s and resubscribe everything', () {
    fakeAsync((async) {
      final transport = FakeTransport();
      final client = build(transport);
      final states = <WsConnectionState>[];
      client.states.listen(states.add);
      client.subscribe('ethusdt@trade').listen((_) {});
      async.elapse(const Duration(seconds: 1));

      transport.failNextConnects = 2;
      transport.last.drop();
      async.flushMicrotasks();
      expect(client.state, WsConnectionState.reconnecting);
      expect(transport.attempts, hasLength(1));

      async.elapse(const Duration(seconds: 1));
      expect(transport.attempts, hasLength(2), reason: 'attempt after 1 s');
      async.elapse(const Duration(seconds: 2));
      expect(
        transport.attempts,
        hasLength(3),
        reason: 'attempt after 2 s more',
      );
      async.elapse(const Duration(seconds: 4));
      expect(
        transport.attempts,
        hasLength(4),
        reason: 'attempt after 4 s more',
      );

      async.elapse(const Duration(seconds: 1));
      expect(client.state, WsConnectionState.connected);
      expect(client.connectionCount, 2);
      final commands = transport.last.commands;
      expect(commands.single['method'], 'SUBSCRIBE');
      expect(paramsOf(commands.single), [heartbeat, 'ethusdt@trade']);
      expect(states.where((s) => s == WsConnectionState.connected).length, 2);
    });
  });

  test('backoff resets after a successful connection', () {
    fakeAsync((async) {
      final transport = FakeTransport();
      final client = build(transport);
      client.subscribe('ethusdt@trade').listen((_) {});
      async.elapse(const Duration(seconds: 1));

      transport.failNextConnects = 1;
      transport.last.drop();
      async
        ..elapse(const Duration(seconds: 1)) // fails
        ..elapse(const Duration(seconds: 2)); // succeeds
      expect(client.state, WsConnectionState.connected);

      transport.last.drop();
      async.elapse(const Duration(milliseconds: 999));
      expect(transport.attempts, hasLength(3));
      async.elapse(const Duration(milliseconds: 1));
      expect(transport.attempts, hasLength(4), reason: 'back to a 1 s delay');
    });
  });

  test('60 s without a data frame recreates the connection', () {
    fakeAsync((async) {
      final transport = FakeTransport();
      final client = build(transport);
      client.subscribe('ethusdt@trade').listen((_) {});
      async.elapse(const Duration(seconds: 1));
      final first = transport.last;

      async.elapse(const Duration(seconds: 50));
      first.push({
        'stream': heartbeat,
        'data': {'c': '1'},
      });
      async.elapse(const Duration(seconds: 50));
      expect(first.closed, isFalse, reason: 'heartbeat frame reset the timer');

      async.elapse(const Duration(seconds: 11));
      expect(first.closed, isTrue, reason: 'silence detected');
      async.elapse(const Duration(seconds: 2));
      expect(transport.connections, hasLength(2));
      expect(client.state, WsConnectionState.connected);
    });
  });

  test(
    'suspend closes without reconnecting; resume reconnects and resubscribes',
    () {
      fakeAsync((async) {
        final transport = FakeTransport();
        final client = build(transport);
        client.subscribe('ethusdt@trade').listen((_) {});
        async.elapse(const Duration(seconds: 1));

        client.suspend();
        async.elapse(const Duration(seconds: 40));
        expect(transport.last.closed, isTrue);
        expect(transport.connections, hasLength(1));
        expect(client.state, WsConnectionState.suspended);

        client.resume();
        async.elapse(const Duration(seconds: 1));
        expect(transport.connections, hasLength(2));
        expect(paramsOf(transport.last.commands.single), [
          heartbeat,
          'ethusdt@trade',
        ]);
      });
    },
  );

  test('heartbeat is not subscribed on its own when nobody listens', () {
    fakeAsync((async) {
      final transport = FakeTransport();
      final client = build(transport);
      async.elapse(const Duration(seconds: 1));
      expect(transport.attempts, isEmpty);
      expect(client.state, WsConnectionState.idle);
    });
  });

  test('dispose closes the socket and the channels', () {
    fakeAsync((async) {
      final transport = FakeTransport();
      final client = build(transport);
      var done = false;
      client
          .subscribe('ethusdt@trade')
          .listen((_) {}, onDone: () => done = true);
      async.elapse(const Duration(seconds: 1));

      client.dispose();
      async.elapse(const Duration(seconds: 1));
      expect(transport.last.closed, isTrue);
      expect(done, isTrue);
    });
  });
}
