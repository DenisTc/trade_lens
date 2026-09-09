import 'dart:convert';

import 'package:meta/meta.dart';

/// Which model to call and what it costs. Lives in Remote Config (key
/// `ai_model`) so a model change or a price change needs no release; the
/// defaults here are the bundled fallback.
@immutable
final class AiModelConfig {
  const AiModelConfig({
    required this.model,
    required this.inputUsdPerMTok,
    required this.outputUsdPerMTok,
    this.maxOutputTokens = 1024,
    this.maxToolIterations = 3,
    this.maxSessionTokens = 40000,
  });

  /// Parses the config JSON; unknown or missing fields keep the defaults,
  /// a broken document returns the defaults.
  factory AiModelConfig.parse(String? json, {AiModelConfig base = defaults}) {
    if (json == null || json.trim().isEmpty) return base;
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return base;
    }
    if (decoded is! Map<String, Object?>) return base;
    final model = decoded['model'];
    return AiModelConfig(
      model: model is String && model.isNotEmpty ? model : base.model,
      inputUsdPerMTok: _num(decoded['inputUsdPerMTok']) ?? base.inputUsdPerMTok,
      outputUsdPerMTok:
          _num(decoded['outputUsdPerMTok']) ?? base.outputUsdPerMTok,
      maxOutputTokens: _int(decoded['maxOutputTokens']) ?? base.maxOutputTokens,
      maxToolIterations:
          _int(decoded['maxToolIterations']) ?? base.maxToolIterations,
      maxSessionTokens:
          _int(decoded['maxSessionTokens']) ?? base.maxSessionTokens,
    );
  }

  /// Cheapest current model; the summary is a description task.
  static const defaults = AiModelConfig(
    model: 'claude-haiku-4-5',
    inputUsdPerMTok: 1,
    outputUsdPerMTok: 5,
  );

  final String model;
  final double inputUsdPerMTok;
  final double outputUsdPerMTok;
  final int maxOutputTokens;

  /// Tool round-trips per summary (spec: 3).
  final int maxToolIterations;

  /// Input + output tokens across all calls of one summary.
  final int maxSessionTokens;

  double costUsd({required int inputTokens, required int outputTokens}) =>
      inputTokens / 1e6 * inputUsdPerMTok +
      outputTokens / 1e6 * outputUsdPerMTok;

  static double? _num(Object? v) => v is num && v >= 0 ? v.toDouble() : null;
  static int? _int(Object? v) => v is int && v > 0 ? v : null;

  @override
  bool operator ==(Object other) =>
      other is AiModelConfig &&
      other.model == model &&
      other.inputUsdPerMTok == inputUsdPerMTok &&
      other.outputUsdPerMTok == outputUsdPerMTok &&
      other.maxOutputTokens == maxOutputTokens &&
      other.maxToolIterations == maxToolIterations &&
      other.maxSessionTokens == maxSessionTokens;

  @override
  int get hashCode => Object.hash(
    model,
    inputUsdPerMTok,
    outputUsdPerMTok,
    maxOutputTokens,
    maxToolIterations,
    maxSessionTokens,
  );
}
