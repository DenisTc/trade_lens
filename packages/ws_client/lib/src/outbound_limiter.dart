import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';

/// Binance allows 5 outgoing messages per second per connection, and the
/// runtime's transport-level pong counts. We keep one message of headroom:
/// four commands per rolling second, everything else waits its turn.
final class OutboundLimiter {
  OutboundLimiter({this.maxPerSecond = 4});

  final int maxPerSecond;
  final Queue<DateTime> _sentAt = Queue();
  Future<void> _tail = Future.value();

  /// Resolves when the caller may send one message. Calls are served in
  /// order so a burst never reorders commands.
  Future<void> acquire() {
    final turn = _tail.then((_) => _waitForSlot());
    _tail = turn;
    return turn;
  }

  Future<void> _waitForSlot() async {
    while (true) {
      final now = clock.now();
      while (_sentAt.isNotEmpty &&
          now.difference(_sentAt.first) >= const Duration(seconds: 1)) {
        _sentAt.removeFirst();
      }
      if (_sentAt.length < maxPerSecond) {
        _sentAt.addLast(now);
        return;
      }
      final wait = const Duration(seconds: 1) - now.difference(_sentAt.first);
      await Future<void>.delayed(wait);
    }
  }
}
