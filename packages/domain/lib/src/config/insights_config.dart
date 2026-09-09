import 'package:meta/meta.dart';

/// Remote configuration the app reads: the SDUI screen JSON and the AI
/// feature flag. Values are raw strings/bools; parsing the screen is the
/// `sdui` package's job so the domain stays free of UI concerns.
@immutable
final class InsightsConfig {
  const InsightsConfig({
    required this.insightsScreenJson,
    required this.aiInsightsEnabled,
    required this.source,
    this.aiModelJson = '',
  });

  final String insightsScreenJson;
  final bool aiInsightsEnabled;

  /// Model id, prices and limits for the AI summary (`ai_model` key);
  /// empty means the bundled defaults.
  final String aiModelJson;

  /// Where the values came from, for the badge and for tests.
  final InsightsConfigOrigin source;

  @override
  bool operator ==(Object other) =>
      other is InsightsConfig &&
      other.insightsScreenJson == insightsScreenJson &&
      other.aiInsightsEnabled == aiInsightsEnabled &&
      other.source == source &&
      other.aiModelJson == aiModelJson;

  @override
  int get hashCode =>
      Object.hash(insightsScreenJson, aiInsightsEnabled, source, aiModelJson);
}

enum InsightsConfigOrigin {
  /// Bundled defaults; nothing fetched yet or the service is unreachable.
  defaults,

  /// Values activated from the remote service.
  remote,
}

/// Keys as they appear in the remote service and in the bundled defaults.
abstract final class InsightsConfigKeys {
  static const insightsScreen = 'insights_screen';
  static const aiInsightsEnabled = 'ai_insights_enabled';
  static const aiModel = 'ai_model';
}

/// Source of [InsightsConfig]. Implementations: Firebase Remote Config
/// (`data_config`), the bundled defaults, fakes in tests.
abstract interface class InsightsConfigSource {
  /// Emits the current config first (defaults until a fetch lands), then
  /// every activated update. Never errors: a failed fetch keeps the last
  /// value and is logged by the implementation.
  Stream<InsightsConfig> watch();

  /// Forces a fetch + activate; resolves when done or timed out.
  Future<void> refresh();
}
