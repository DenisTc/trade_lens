import 'dart:async';

import 'package:core/core.dart';
import 'package:domain/domain.dart';

/// One polling loop shared by every `quoteStream` of the CoinGecko source.
///
/// Family providers open one stream per row; without sharing, twenty rows
/// would mean twenty `simple/price` requests a minute against a quota that
/// is shared by every install. The poller keeps a reference count per
/// instrument, fetches the union in one batch and fans quotes out.
final class QuotePoller {
  QuotePoller({
    required this.fetch,
    this.interval = const Duration(seconds: 60),
  });

  /// Batched fetch of the wanted instruments.
  final Future<Result<List<Quote>, MarketError>> Function(
    List<Instrument> instruments,
  )
  fetch;
  final Duration interval;

  final Map<Instrument, int> _wanted = {};
  final StreamController<Quote> _quotes = StreamController.broadcast();
  final StreamController<MarketError> _errors = StreamController.broadcast();
  Timer? _timer;
  Timer? _kick;
  int _generation = 0;

  /// Instruments currently polled, for tests and diagnostics.
  Set<Instrument> get wanted => Set.unmodifiable(_wanted.keys);

  Stream<Quote> streamFor(List<Instrument> instruments) {
    final symbols = {for (final i in instruments) i.symbol};
    late StreamController<Quote> out;
    StreamSubscription<Quote>? quotes;
    StreamSubscription<MarketError>? errors;
    out = StreamController<Quote>(
      onListen: () {
        quotes = _quotes.stream
            .where((q) => symbols.contains(q.instrument.symbol))
            .listen(out.add);
        errors = _errors.stream.listen(out.addError);
        for (final instrument in instruments) {
          _wanted[instrument] = (_wanted[instrument] ?? 0) + 1;
        }
        _ensureRunning();
        // Listeners arriving in the same tick (a list of rows) share one
        // immediate request.
        _kick ??= Timer(Duration.zero, () {
          _kick = null;
          unawaited(_poll());
        });
      },
      onCancel: () {
        unawaited(quotes?.cancel());
        unawaited(errors?.cancel());
        for (final instrument in instruments) {
          final next = (_wanted[instrument] ?? 1) - 1;
          if (next <= 0) {
            _wanted.remove(instrument);
          } else {
            _wanted[instrument] = next;
          }
        }
        if (_wanted.isEmpty) _stop();
      },
    );
    return out.stream;
  }

  void _ensureRunning() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(_poll()));
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _kick?.cancel();
    _kick = null;
    _generation++;
  }

  Future<void> _poll() async {
    final instruments = _wanted.keys.toList();
    if (instruments.isEmpty) return;
    final generation = _generation;
    final result = await fetch(instruments);
    if (generation != _generation) return; // everyone left meanwhile
    result.when(ok: (batch) => batch.forEach(_quotes.add), err: _errors.add);
  }

  Future<void> dispose() async {
    _stop();
    await _quotes.close();
    await _errors.close();
  }
}
