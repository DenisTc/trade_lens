import 'dart:async';

import 'package:core/core.dart';
import 'package:data_config/data_config.dart';
import 'package:domain/domain.dart';
import 'package:features_insights/features_insights.dart';
import 'package:features_shared/features_shared.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tradelens/firebase_options.dart';

part 'config_di.g.dart';

/// Project id of the stub written by `tooling/scripts/firebase_stub.sh`.
const stubFirebaseProjectId = 'tradelens-stub';

/// Initialises Firebase; false when the generated options are the stub
/// (forks, CI) or the platform refuses, in which case the app runs on the
/// bundled defaults. Never throws: the config is a nice-to-have.
Future<bool> initFirebase() async {
  if (!(defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android)) {
    return false;
  }
  final options = DefaultFirebaseOptions.currentPlatform;
  // `tooling/scripts/firebase_stub.sh` writes this project id when the real
  // (git-ignored) configuration is absent.
  if (options.projectId == stubFirebaseProjectId) return false;
  try {
    await Firebase.initializeApp(options: options);
    return true;
  } on Object catch (e, st) {
    debugPrint('[tradelens] Firebase init failed: $e');
    await Sentry.captureException(e, stackTrace: st);
    return false;
  }
}

/// Bundled defaults, loaded once; both the Remote Config defaults and the
/// last-resort screen.
@Riverpod(keepAlive: true)
Future<InsightsConfig> insightsDefaults(Ref ref) async => InsightsConfig(
  insightsScreenJson: await loadInsightsDefaultJson(),
  aiInsightsEnabled: false,
  source: InsightsConfigOrigin.defaults,
);

/// Remote Config when Firebase is up, defaults otherwise. The source is
/// created lazily around the async defaults, so `watch()` still emits the
/// defaults first.
@Riverpod(keepAlive: true)
InsightsConfigSource appInsightsConfigSource(
  Ref ref, {
  required bool firebase,
}) {
  final source = _LazyInsightsConfigSource(
    ref.watch(insightsDefaultsProvider.future),
    (defaults) => firebase
        ? RemoteInsightsConfigSource(
            client: FirebaseRemoteConfigClient(FirebaseRemoteConfig.instance),
            defaults: defaults,
            logger: const PrintLogger(),
          )
        : DefaultsInsightsConfigSource(defaults),
  );
  ref.onDispose(source.dispose);
  return source;
}

/// Sentry for handled errors, with the console log as well in debug.
final class SentryErrorReporter implements ErrorReporter {
  const SentryErrorReporter();

  @override
  void report(Object error, {StackTrace? stackTrace, String? hint}) {
    debugPrint('[tradelens] ${hint ?? 'handled error'}: $error');
    unawaited(
      Sentry.captureException(
        error,
        stackTrace: stackTrace,
        hint: hint == null ? null : Hint.withMap({'hint': hint}),
      ),
    );
  }
}

List<Override> configOverrides({required bool firebase}) => [
  insightsConfigSourceProvider.overrideWith(
    (ref) => ref.watch(appInsightsConfigSourceProvider(firebase: firebase)),
  ),
  errorReporterProvider.overrideWithValue(const SentryErrorReporter()),
];

/// Waits for the async defaults, then delegates to the real source.
final class _LazyInsightsConfigSource implements InsightsConfigSource {
  _LazyInsightsConfigSource(this._defaults, this._build);

  final Future<InsightsConfig> _defaults;
  final InsightsConfigSource Function(InsightsConfig defaults) _build;
  Future<InsightsConfigSource>? _inner;

  Future<InsightsConfigSource> get _source => _inner ??= _defaults.then(_build);

  Future<InsightsConfigSource> _resolved() => _source;

  @override
  Stream<InsightsConfig> watch() async* {
    yield* (await _source).watch();
  }

  @override
  Future<void> refresh() async {
    final source = await _resolved();
    await source.refresh();
  }

  Future<void> dispose() async {
    final inner = await (_inner ?? Future<InsightsConfigSource?>.value());
    if (inner is RemoteInsightsConfigSource) await inner.dispose();
  }
}
