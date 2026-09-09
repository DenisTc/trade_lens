import 'dart:async';

import 'package:core/core.dart';
import 'package:data_config/src/remote_config_client.dart';
import 'package:domain/domain.dart';
import 'package:flutter/foundation.dart';

/// Firebase Remote Config behind [InsightsConfigSource].
///
/// - Defaults are set first, so the first emitted value is the bundled
///   screen and nothing waits on the network.
/// - `fetchAndActivate` runs once with a timeout; a failure or timeout is
///   logged and the defaults stay.
/// - Realtime updates (`onConfigUpdated`) are activated as they arrive, so
///   an edit in the console shows up live during a demo.
/// - Minimum fetch interval is zero in debug builds, 12 h in release.
///
/// Lifecycle: the realtime subscription is opened on the first listener
/// and closed synchronously when the last one leaves, so cancel/relisten
/// cannot race; [dispose] fences everything against a later restart.
final class RemoteInsightsConfigSource implements InsightsConfigSource {
  RemoteInsightsConfigSource({
    required RemoteConfigClient client,
    required InsightsConfig defaults,
    Logger logger = const NoopLogger(),
    Duration fetchTimeout = const Duration(seconds: 8),
    Duration? minimumFetchInterval,
  }) : this._(
         client,
         defaults,
         logger,
         fetchTimeout,
         minimumFetchInterval ??
             (kDebugMode ? Duration.zero : const Duration(hours: 12)),
       );

  RemoteInsightsConfigSource._(
    this._client,
    this._defaults,
    this._logger,
    this._fetchTimeout,
    this._minimumFetchInterval,
  );

  final RemoteConfigClient _client;
  final InsightsConfig _defaults;
  final Logger _logger;
  final Duration _fetchTimeout;
  final Duration _minimumFetchInterval;

  late final StreamController<InsightsConfig> _controller =
      StreamController<InsightsConfig>.broadcast(
        onListen: _start,
        onCancel: _stop,
      );
  InsightsConfig? _current;

  /// Cancelled in [_stop].
  StreamSubscription<Set<String>>? _updates;
  Future<void>? _configured;
  Future<void>? _fetching;
  Future<void> _stopping = Future.value();
  var _disposed = false;

  InsightsConfig get current => _current ?? _defaults;

  /// The current value, then every activated change. The subscription to
  /// the broadcast stream is taken before the snapshot is delivered, so an
  /// update landing in between is not lost.
  @override
  Stream<InsightsConfig> watch() {
    late final StreamController<InsightsConfig> out;
    StreamSubscription<InsightsConfig>? sub;
    out = StreamController<InsightsConfig>(
      onListen: () {
        if (_disposed) {
          out.add(current);
          unawaited(out.close());
          return;
        }
        sub = _controller.stream.listen(out.add, onDone: out.close);
        out.add(current);
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  /// One fetch at a time; a second call while one runs shares its future.
  @override
  Future<void> refresh() async {
    if (_disposed) return;
    await (_configured ??= _configure());
    if (_disposed) return;
    await (_fetching ??= _fetch().whenComplete(() => _fetching = null));
  }

  void _start() {
    if (_disposed) return;
    unawaited(refresh());
    late final StreamSubscription<Set<String>> subscription;
    subscription = _client.onUpdated.listen(
      (keys) async {
        try {
          await _client.activate();
          if (identical(_updates, subscription)) _emit();
        } on Object catch (e, st) {
          _logger
            ..warn('remote config activate failed', e)
            ..debug('$st');
        }
      },
      onError: (Object e) =>
          _logger.warn('remote config realtime stream failed', e),
    );
    _updates = subscription;
  }

  /// Detaches synchronously: `onCancel` of a broadcast controller is not
  /// awaited, so a relisten must find `_updates` already null. The old
  /// subscription's cancel completes on its own; nothing it could still
  /// deliver reaches the controller because the handler checks the
  /// subscription is current.
  void _stop() {
    final updates = _updates;
    _updates = null;
    if (updates != null) _stopping = _stopping.then((_) => updates.cancel());
  }

  Future<void> _configure() async {
    try {
      await _client.configure(
        fetchTimeout: _fetchTimeout,
        minimumFetchInterval: _minimumFetchInterval,
        defaults: {
          InsightsConfigKeys.insightsScreen: _defaults.insightsScreenJson,
          InsightsConfigKeys.aiInsightsEnabled: _defaults.aiInsightsEnabled,
        },
      );
    } on Object catch (e) {
      _logger.warn('remote config configure failed', e);
    }
  }

  Future<void> _fetch() async {
    try {
      await _client.fetchAndActivate().timeout(
        _fetchTimeout + const Duration(seconds: 2),
      );
      _emit();
    } on Object catch (e) {
      _logger.warn('remote config fetch failed, keeping defaults', e);
    }
  }

  void _emit() {
    if (_disposed) return;
    final origin =
        _client.originOf(InsightsConfigKeys.insightsScreen) ==
            RemoteValueOrigin.remote
        ? InsightsConfigOrigin.remote
        : InsightsConfigOrigin.defaults;
    final next = InsightsConfig(
      insightsScreenJson: _client.getString(InsightsConfigKeys.insightsScreen),
      aiInsightsEnabled: _client.getBool(InsightsConfigKeys.aiInsightsEnabled),
      source: origin,
    );
    if (next == current) return;
    _current = next;
    _controller.add(next);
  }

  /// Completes once the realtime subscription's cancellation has finished.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stop();
    await _stopping;
    await _controller.close();
  }
}

/// Bundled defaults only, for builds without Firebase configuration
/// (forks, CI) and for tests.
final class DefaultsInsightsConfigSource implements InsightsConfigSource {
  const DefaultsInsightsConfigSource(this.defaults);

  final InsightsConfig defaults;

  @override
  Stream<InsightsConfig> watch() => Stream.value(defaults);

  @override
  Future<void> refresh() async {}
}
