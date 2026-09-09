import 'package:domain/domain.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'config.g.dart';

/// Remote configuration source. Declared without an implementation; the
/// app overrides it with Firebase Remote Config (or the bundled defaults
/// when Firebase is not configured).
@Riverpod(keepAlive: true)
InsightsConfigSource insightsConfigSource(Ref ref) {
  throw UnimplementedError(
    'insightsConfigSourceProvider must be overridden by the app',
  );
}

/// Current config; the first value is the defaults so nothing waits on
/// the network.
@Riverpod(keepAlive: true)
Stream<InsightsConfig> insightsConfig(Ref ref) =>
    ref.watch(insightsConfigSourceProvider).watch();

/// Feature flag for the AI summary, false until the config says otherwise.
@riverpod
bool aiInsightsEnabled(Ref ref) =>
    ref.watch(insightsConfigProvider).value?.aiInsightsEnabled ?? false;
