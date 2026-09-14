import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:ws_client/src/backoff.dart';
import 'package:ws_client/src/outbound_limiter.dart';
import 'package:ws_client/src/protocol.dart';
import 'package:ws_client/src/subscription_registry.dart';
import 'package:ws_client/src/transport.dart';

enum WsConnectionState { idle, connecting, connected, reconnecting, suspended }

/// One data frame: the stream it belongs to and its payload, as the
/// exchange's [WsProtocol] decoded them.
final class WsMessage {
  const WsMessage({required this.stream, required this.data});

  final String stream;
  final Map<String, Object?> data;

  @override
  String toString() => 'WsMessage($stream)';
}

/// One connection per source, combined stream, subscriptions managed by a
/// reference-counted registry.
///
/// - The exchange subscription opens on the first listener and closes
///   [unsubscribeDelay] after the last one leaves, so screen transitions do
///   not churn the socket.
/// - Registry changes within [batchWindow] become one `SUBSCRIBE` and one
///   `UNSUBSCRIBE`; every outgoing message passes the [OutboundLimiter].
/// - [heartbeatStream] (a liquid miniTicker) is kept subscribed whenever
///   anything else is, so [silenceTimeout] without a data frame of a
///   wanted stream means the connection is dead, not the market quiet. The
///   runtime answers transport pings by itself and never shows them here.
/// - Reconnect with [Backoff]; after reconnecting every wanted stream is
///   re-subscribed. Consumers watch [states] to backfill what they missed.
///
/// Every socket belongs to a *generation*. Teardown bumps the generation,
/// so a connect that completes late (after suspend, dispose or a newer
/// connect) closes its socket instead of taking over.
final class WsClient {
  WsClient({
    required this._transport,
    required this.url,
    this.logger = const NoopLogger(),
    this.silenceTimeout = const Duration(seconds: 60),
    this.batchWindow = const Duration(milliseconds: 250),
    this.unsubscribeDelay = const Duration(seconds: 2),
    this.heartbeatStream,
    this.protocol = const BinanceWsProtocol(),
    Backoff? backoff,
    OutboundLimiter? limiter,
  }) : _backoff = backoff ?? Backoff(),
       _limiter = limiter ?? OutboundLimiter();

  final Uri url;
  final Logger logger;
  final Duration silenceTimeout;
  final Duration batchWindow;
  final Duration unsubscribeDelay;
  final String? heartbeatStream;

  /// The exchange's wire format; Binance unless told otherwise.
  final WsProtocol protocol;

  final WsTransport _transport;
  final Backoff _backoff;
  final OutboundLimiter _limiter;
  final SubscriptionRegistry _registry = SubscriptionRegistry();
  final Set<String> _serverSubscriptions = {};

  /// Streams to drop and take again on the next sync, for a consumer
  /// whose state depends on the snapshot an exchange sends on subscribe.
  final Set<String> _resubscribe = {};
  final Map<String, StreamController<WsMessage>> _channels = {};
  final Map<String, Timer> _pendingUnsubscribes = {};
  final StreamController<WsConnectionState> _states =
      StreamController.broadcast();

  WsConnectionState _state = WsConnectionState.idle;
  WsConnection? _connection;
  // Cancelled in _teardown.
  // ignore: cancel_subscriptions
  StreamSubscription<String>? _frames;
  Timer? _batchTimer;
  Timer? _silenceTimer;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _generation = 0;
  int _commandId = 0;
  int _connectionCount = 0;
  bool _connecting = false;
  bool _syncing = false;
  bool _syncAgain = false;
  bool _suspended = false;
  bool _disposed = false;

  WsConnectionState get state => _state;

  /// State transitions; `connected` after `reconnecting` is the signal to
  /// backfill.
  Stream<WsConnectionState> get states => _states.stream;

  /// How many times a connection was established (1 = first connect).
  int get connectionCount => _connectionCount;

  int listenerCount(String stream) => _registry.count(stream);

  /// Streams currently subscribed on the exchange (as far as we know).
  Set<String> get serverSubscriptions => Set.unmodifiable(_serverSubscriptions);

  /// Asks the exchange for [stream] afresh: unsubscribe, then subscribe,
  /// which makes an exchange resend whatever it sends on subscribe — a
  /// book snapshot, for one. A no-op when nobody listens to [stream].
  void resubscribe(String stream) {
    if (_registry.count(stream) == 0) return;
    _resubscribe.add(stream);
    _markDirty();
  }

  /// Frames of [stream]. Listening registers a consumer; cancelling
  /// unregisters it. Nothing is subscribed on the exchange until the first
  /// listener arrives.
  Stream<WsMessage> subscribe(String stream) {
    late StreamController<WsMessage> out;
    StreamSubscription<WsMessage>? inner;
    out = StreamController<WsMessage>(
      onListen: () {
        _addListener(stream);
        inner = _channel(stream).stream
            .listen(out.add, onError: out.addError, onDone: out.close);
      },
      onPause: () => inner?.pause(),
      onResume: () => inner?.resume(),
      onCancel: () {
        _removeListener(stream);
        unawaited(inner?.cancel());
      },
    );
    return out.stream;
  }

  /// Background: close the socket, do not reconnect until [resume].
  void suspend() {
    if (_disposed || _suspended) return;
    _suspended = true;
    _cancelReconnect();
    _teardown();
    _setState(WsConnectionState.suspended);
  }

  /// Foreground: reconnect if anything is wanted.
  void resume() {
    if (_disposed || !_suspended) return;
    _suspended = false;
    if (_wanted.isEmpty) {
      _setState(WsConnectionState.idle);
      return;
    }
    unawaited(_connect());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _batchTimer?.cancel();
    _cancelReconnect();
    for (final timer in _pendingUnsubscribes.values) {
      timer.cancel();
    }
    _pendingUnsubscribes.clear();
    _teardown();
    for (final channel in _channels.values) {
      await channel.close();
    }
    _channels.clear();
    await _states.close();
  }

  // ---------------------------------------------------------------- registry

  /// Streams that must be subscribed: everything with a listener, streams
  /// inside their unsubscribe grace period, plus the heartbeat while any
  /// of those exist.
  Set<String> get _wanted {
    final wanted = _registry.wanted..addAll(_pendingUnsubscribes.keys);
    final heartbeat = heartbeatStream;
    if (wanted.isNotEmpty && heartbeat != null) wanted.add(heartbeat);
    return wanted;
  }

  void _addListener(String stream) {
    if (_disposed) throw StateError('WsClient is disposed');
    _pendingUnsubscribes.remove(stream)?.cancel();
    if (_registry.add(stream) == 1) _markDirty();
    if (_state == WsConnectionState.idle && !_suspended) {
      unawaited(_connect());
    }
  }

  void _removeListener(String stream) {
    if (_disposed) return;
    if (_registry.remove(stream) > 0) return;
    _pendingUnsubscribes[stream] = Timer(unsubscribeDelay, () {
      _pendingUnsubscribes.remove(stream);
      if (_registry.count(stream) == 0) _markDirty();
    });
  }

  StreamController<WsMessage> _channel(String stream) =>
      _channels.putIfAbsent(stream, StreamController<WsMessage>.broadcast);

  void _markDirty() {
    _batchTimer ??= Timer(batchWindow, () {
      _batchTimer = null;
      unawaited(_sync());
    });
  }

  /// Brings the exchange subscriptions in line with the registry. Runs one
  /// at a time; a change during a run schedules another pass.
  Future<void> _sync() async {
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      await _syncOnce();
    } finally {
      _syncing = false;
      if (_syncAgain && !_disposed) {
        _syncAgain = false;
        unawaited(_sync());
      }
    }
  }

  Future<void> _syncOnce() async {
    if (_disposed) return;
    final wanted = _wanted;
    final connection = _connection;
    if (wanted.isEmpty) {
      if (connection != null) {
        logger.info('no listeners left, closing socket');
        _teardown();
      }
      _cancelReconnect();
      if (!_suspended) _setState(WsConnectionState.idle);
      return;
    }
    if (connection == null || _state != WsConnectionState.connected) return;

    final refresh = _serverSubscriptions.intersection(_resubscribe);
    _resubscribe.clear();
    final toUnsubscribe = _serverSubscriptions.difference(wanted).union(refresh)
      ..toList();
    for (final batch in _batches(toUnsubscribe.toList()..sort())) {
      if (!await _send(connection, protocol.unsubscribe, batch)) return;
      _serverSubscriptions.removeAll(batch);
    }
    // Re-read: listeners may have changed while the limiter held us.
    final toSubscribe = _wanted.difference(_serverSubscriptions).toList()
      ..sort();
    for (final batch in _batches(toSubscribe)) {
      if (!await _send(connection, protocol.subscribe, batch)) return;
      _serverSubscriptions.addAll(batch);
    }
  }

  /// One command per [WsProtocol.maxStreamsPerCommand] streams; an
  /// exchange that caps the count rejects everything past it.
  Iterable<List<String>> _batches(List<String> streams) sync* {
    final size = protocol.maxStreamsPerCommand;
    if (size == null || streams.length <= size) {
      if (streams.isNotEmpty) yield streams;
      return;
    }
    for (var i = 0; i < streams.length; i += size) {
      yield streams.sublist(
        i,
        i + size > streams.length ? streams.length : i + size,
      );
    }
  }

  /// False when the socket changed while waiting for a send slot; the new
  /// socket gets its own sync.
  Future<bool> _send(
    WsConnection connection,
    String Function(List<String> streams, int id) encode,
    List<String> streams,
  ) async {
    await _limiter.acquire();
    if (!identical(connection, _connection)) return false;
    final command = encode(streams, ++_commandId);
    logger.debug('→ $command');
    connection.send(command);
    return true;
  }

  /// Exchanges that close a quiet socket want a ping from the client;
  /// it bypasses the limiter, which exists for subscription commands.
  void _armPingTimer() {
    _pingTimer?.cancel();
    final ping = protocol.ping;
    final interval = protocol.pingInterval;
    if (ping == null || interval == null) return;
    _pingTimer = Timer.periodic(interval, (_) => _connection?.send(ping));
  }

  // -------------------------------------------------------------- connection

  Future<void> _connect() async {
    if (_disposed || _suspended || _connection != null || _connecting) return;
    if (_wanted.isEmpty) {
      _cancelReconnect();
      _setState(WsConnectionState.idle);
      return;
    }
    _reconnectTimer = null;
    _connecting = true;
    final generation = _generation;
    _setState(
      _connectionCount == 0
          ? WsConnectionState.connecting
          : WsConnectionState.reconnecting,
    );
    final WsConnection connection;
    try {
      connection = await _transport.connect(url);
    } on Object catch (e) {
      _connecting = false;
      if (_disposed || _suspended) return;
      if (generation != _generation) {
        unawaited(_connect()); // a newer generation wants a socket
        return;
      }
      logger.warn('connect failed', e);
      _scheduleReconnect();
      return;
    }
    _connecting = false;
    if (_disposed || _suspended || generation != _generation) {
      // Stale: suspend/teardown happened while the handshake was in flight.
      unawaited(connection.close());
      if (!_disposed && !_suspended) unawaited(_connect());
      return;
    }
    _connection = connection;
    _connectionCount++;
    _backoff.reset();
    _serverSubscriptions.clear();
    _frames = connection.messages.listen(
      _onFrame,
      onError: (Object e) {
        logger.warn('socket error', e);
        _onClosed();
      },
      onDone: _onClosed,
    );
    _setState(WsConnectionState.connected);
    _armSilenceTimer();
    _armPingTimer();
    // Not synced right away: the batch window collects subscriptions that
    // arrived while connecting into one command.
    _markDirty();
  }

  void _onFrame(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      logger.warn('bad frame', e);
      return;
    }
    if (json is! Map<String, Object?>) return;
    // Command acknowledgements, pongs and errors do not prove the data
    // path is alive: the silence timer stays as is.
    final decoded = protocol.decode(json);
    if (decoded == null) return;
    final (:stream, :data) = decoded;
    if (!_wanted.contains(stream)) return;
    _armSilenceTimer();
    _channels[stream]?.add(WsMessage(stream: stream, data: data));
  }

  void _armSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(silenceTimeout, () {
      if (_connection == null || _wanted.isEmpty) return;
      logger.warn('no data for $silenceTimeout, assuming half-open socket');
      _onClosed();
    });
  }

  /// The socket is gone (peer closed, error, silence): tear down and decide
  /// what comes next.
  void _onClosed() {
    if (_connection == null) return; // already handled
    _teardown();
    if (_disposed) return;
    if (_suspended) {
      _setState(WsConnectionState.suspended);
      return;
    }
    if (_wanted.isEmpty) {
      _setState(WsConnectionState.idle);
      return;
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _setState(WsConnectionState.reconnecting);
    final delay = _backoff.next();
    logger.info('reconnect in $delay (attempt ${_backoff.attempt})');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => unawaited(_connect()));
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// Drops the current socket synchronously and invalidates in-flight
  /// connects. Close futures are not awaited: the state machine must not
  /// depend on how fast a peer acknowledges.
  void _teardown() {
    _generation++;
    _silenceTimer?.cancel();
    _pingTimer?.cancel();
    _pingTimer = null;
    final connection = _connection;
    final frames = _frames;
    _connection = null;
    _frames = null;
    _serverSubscriptions.clear();
    unawaited(frames?.cancel());
    unawaited(
      connection?.close().catchError((Object e) {
        logger.warn('close failed', e);
      }),
    );
  }

  void _setState(WsConnectionState next) {
    if (_state == next) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }
}
