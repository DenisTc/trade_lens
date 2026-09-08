import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:ws_client/src/backoff.dart';
import 'package:ws_client/src/outbound_limiter.dart';
import 'package:ws_client/src/subscription_registry.dart';
import 'package:ws_client/src/transport.dart';

enum WsConnectionState { idle, connecting, connected, reconnecting, suspended }

/// One frame of a combined stream: `{"stream": "...", "data": {...}}`.
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
///   anything else is, so [silenceTimeout] without a data frame means the
///   connection is dead, not the market quiet. The runtime answers
///   transport pings by itself and never shows them here.
/// - Reconnect with [Backoff]; after reconnecting every wanted stream is
///   re-subscribed. Consumers watch [states] to backfill what they missed.
final class WsClient {
  WsClient({
    required this._transport,
    required this.url,
    this.logger = const NoopLogger(),
    this.silenceTimeout = const Duration(seconds: 60),
    this.batchWindow = const Duration(milliseconds: 250),
    this.unsubscribeDelay = const Duration(seconds: 2),
    this.heartbeatStream,
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

  final WsTransport _transport;
  final Backoff _backoff;
  final OutboundLimiter _limiter;
  final SubscriptionRegistry _registry = SubscriptionRegistry();
  final Set<String> _serverSubscriptions = {};
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
  Timer? _reconnectTimer;
  int _commandId = 0;
  int _connectionCount = 0;
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
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
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
    _silenceTimer?.cancel();
    _reconnectTimer?.cancel();
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

  Set<String> get _wanted {
    final wanted = _registry.wanted;
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

  /// Brings the exchange subscriptions in line with the registry.
  Future<void> _sync() async {
    final connection = _connection;
    if (_disposed ||
        connection == null ||
        _state != WsConnectionState.connected) {
      return;
    }
    final wanted = _wanted;
    if (wanted.isEmpty) {
      logger.info('no listeners left, closing socket');
      _teardown();
      _setState(WsConnectionState.idle);
      return;
    }
    final toSubscribe = wanted.difference(_serverSubscriptions).toList()
      ..sort();
    final toUnsubscribe = _serverSubscriptions.difference(wanted).toList()
      ..sort();
    if (toUnsubscribe.isNotEmpty) {
      _serverSubscriptions.removeAll(toUnsubscribe);
      await _send(connection, 'UNSUBSCRIBE', toUnsubscribe);
    }
    if (toSubscribe.isNotEmpty) {
      _serverSubscriptions.addAll(toSubscribe);
      await _send(connection, 'SUBSCRIBE', toSubscribe);
    }
  }

  Future<void> _send(
    WsConnection connection,
    String method,
    List<String> params,
  ) async {
    await _limiter.acquire();
    if (!identical(connection, _connection)) return; // socket changed meanwhile
    final command = jsonEncode({
      'method': method,
      'params': params,
      'id': ++_commandId,
    });
    logger.debug('→ $command');
    connection.send(command);
  }

  // -------------------------------------------------------------- connection

  Future<void> _connect() async {
    if (_disposed || _suspended || _connection != null) return;
    if (_state == WsConnectionState.connecting ||
        (_state == WsConnectionState.reconnecting && _reconnectTimer == null)) {
      return;
    }
    _reconnectTimer = null;
    _setState(
      _connectionCount == 0
          ? WsConnectionState.connecting
          : WsConnectionState.reconnecting,
    );
    final WsConnection connection;
    try {
      connection = await _transport.connect(url);
    } on Object catch (e) {
      if (_disposed || _suspended) return;
      logger.warn('connect failed', e);
      _scheduleReconnect();
      return;
    }
    if (_disposed || _suspended) {
      await connection.close();
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
    // Not synced right away: the batch window collects subscriptions that
    // arrived while connecting into one command.
    _markDirty();
  }

  void _onFrame(String text) {
    _armSilenceTimer();
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      logger.warn('bad frame', e);
      return;
    }
    if (json is! Map<String, Object?>) return;
    final stream = json['stream'];
    final data = json['data'];
    if (stream is! String || data is! Map<String, Object?>) {
      // Command acknowledgements: {"result": null, "id": n}.
      return;
    }
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

  /// Drops the current socket synchronously. Close futures are not awaited:
  /// the state machine must not depend on how fast a peer acknowledges.
  void _teardown() {
    _silenceTimer?.cancel();
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
