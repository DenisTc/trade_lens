import 'package:firebase_remote_config/firebase_remote_config.dart';

/// Where a value came from, mirroring Firebase's `ValueSource`.
enum RemoteValueOrigin { static, defaults, remote }

/// The slice of Firebase Remote Config the source needs, as an interface
/// so the source is unit-testable without platform channels.
abstract interface class RemoteConfigClient {
  Future<void> configure({
    required Duration fetchTimeout,
    required Duration minimumFetchInterval,
    required Map<String, Object> defaults,
  });

  /// Fetches and activates; true when new values were activated.
  Future<bool> fetchAndActivate();

  /// Activates already fetched values (after a realtime update).
  Future<bool> activate();

  /// Realtime updates from the console; each event carries changed keys.
  Stream<Set<String>> get onUpdated;

  String getString(String key);
  bool getBool(String key);
  RemoteValueOrigin originOf(String key);
}

/// The real thing.
final class FirebaseRemoteConfigClient implements RemoteConfigClient {
  FirebaseRemoteConfigClient(this._rc);

  final FirebaseRemoteConfig _rc;

  @override
  Future<void> configure({
    required Duration fetchTimeout,
    required Duration minimumFetchInterval,
    required Map<String, Object> defaults,
  }) async {
    await _rc.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: fetchTimeout,
        minimumFetchInterval: minimumFetchInterval,
      ),
    );
    await _rc.setDefaults(defaults);
  }

  @override
  Future<bool> fetchAndActivate() => _rc.fetchAndActivate();

  @override
  Future<bool> activate() => _rc.activate();

  @override
  Stream<Set<String>> get onUpdated =>
      _rc.onConfigUpdated.map((e) => e.updatedKeys);

  @override
  String getString(String key) => _rc.getString(key);

  @override
  bool getBool(String key) => _rc.getBool(key);

  @override
  RemoteValueOrigin originOf(String key) => switch (_rc.getValue(key).source) {
    ValueSource.valueRemote => RemoteValueOrigin.remote,
    ValueSource.valueDefault => RemoteValueOrigin.defaults,
    ValueSource.valueStatic => RemoteValueOrigin.static,
  };
}
