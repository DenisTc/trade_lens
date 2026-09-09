import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sdui/sdui.dart';

part 'insights_model.g.dart';

/// Path of the bundled screen inside this package.
const insightsDefaultAsset =
    'packages/features_insights/assets/sdui/insights_default.json';

/// Loads the bundled default JSON. The app uses it both as the Remote
/// Config default and as the last-resort screen. Not cached: the bundle
/// cache keeps a future from the first caller's zone, which never resolves
/// for a later widget test running in its own fake-async zone.
Future<String> loadInsightsDefaultJson() =>
    rootBundle.loadString(insightsDefaultAsset, cache: false);

/// Provider around [loadInsightsDefaultJson] so tests can slow it down.
@Riverpod(keepAlive: true)
Future<String> Function() insightsDefaultLoader(Ref ref) =>
    loadInsightsDefaultJson;

/// What the screen shows and where it came from.
final class InsightsState {
  const InsightsState({required this.screen, required this.origin});

  final SduiScreen screen;
  final InsightsConfigOrigin origin;
}

/// The screen to show for the current config (spec, "Remote Config и
/// SDUI"):
///
/// - a valid config is the screen;
/// - a broken config (invalid JSON, a missing or mistyped field) is
///   reported and ignored, the previous valid screen stays;
/// - a config with a newer schema than this app understands shows the
///   bundled screen, because the previous one may be stale by design;
/// - with nothing valid seen yet, the bundled screen.
///
/// Kept alive: the last valid screen must survive the tab being left and
/// re-entered, otherwise a retained bad config would degrade to defaults
/// on every return. A build that awaited the asset while a newer config
/// arrived discards its result (`_generation`).
@Riverpod(keepAlive: true)
class InsightsModel extends _$InsightsModel {
  InsightsState? _last;
  var _generation = 0;

  @override
  Future<InsightsState> build() async {
    final generation = ++_generation;
    final config = await ref.watch(insightsConfigProvider.future);
    if (generation != _generation && _last != null) return _last!;
    final parsed = SduiParser.parse(config.insightsScreenJson);
    switch (parsed) {
      case Ok(:final value):
        return _last = InsightsState(screen: value, origin: config.source);
      case Err(:final error):
        ref
            .read(errorReporterProvider)
            .report(error, hint: 'insights_screen config rejected');
        if (!isUnsupportedSchema(error) && _last != null) return _last!;
        final fallback = SduiParser.parse(
          await ref.read(insightsDefaultLoaderProvider)(),
        );
        final state = InsightsState(
          screen:
              fallback.valueOrNull ??
              const SduiScreen(schema: sduiSupportedSchema, children: []),
          origin: InsightsConfigOrigin.defaults,
        );
        if (generation != _generation && _last != null) return _last!;
        return _last = state;
    }
  }
}
