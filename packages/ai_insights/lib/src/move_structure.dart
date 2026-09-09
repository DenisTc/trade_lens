import 'dart:convert';

import 'package:core/core.dart';
import 'package:meta/meta.dart';

enum Trend { up, down, sideways }

enum Volatility { low, medium, high }

/// The structured block under the prose: the second call's JSON output.
@immutable
final class MoveStructure {
  const MoveStructure({
    required this.trend,
    required this.volatility,
    required this.keyLevels,
    required this.dataSource,
    required this.dataAsOf,
  });

  final Trend trend;
  final Volatility volatility;

  /// Price levels the model named, as decimal strings in the quote currency.
  final List<String> keyLevels;
  final String dataSource;
  final DateTime dataAsOf;

  /// More than this many levels would not fit the block; the extra ones
  /// are dropped rather than failing the whole answer.
  static const maxKeyLevels = 6;

  /// JSON schema sent as `output_config.format`. Keyword support is
  /// limited for structured outputs, so bounds live in descriptions and
  /// are enforced here instead.
  static const schema = <String, Object?>{
    'type': 'object',
    'properties': {
      'trend': {
        'type': 'string',
        'enum': ['up', 'down', 'sideways'],
      },
      'volatility': {
        'type': 'string',
        'enum': ['low', 'medium', 'high'],
      },
      'keyLevels': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'At most $maxKeyLevels price levels.',
      },
      'dataSource': {'type': 'string'},
      'dataAsOf': {'type': 'string', 'description': 'ISO-8601 UTC timestamp'},
    },
    'required': ['trend', 'volatility', 'keyLevels', 'dataSource', 'dataAsOf'],
    'additionalProperties': false,
  };

  /// The same block with the source the data actually came from.
  MoveStructure withSource(String source) => MoveStructure(
    trend: trend,
    volatility: volatility,
    keyLevels: keyLevels,
    dataSource: source,
    dataAsOf: dataAsOf,
  );

  /// Strict parse of the model's JSON: a wrong type or an unknown enum
  /// value is an error, never a guess.
  static Result<MoveStructure, String> parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      return Err('invalid JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) return const Err('not an object');
    final trend = _enum(Trend.values, decoded['trend']);
    if (trend == null) return const Err('trend');
    final volatility = _enum(Volatility.values, decoded['volatility']);
    if (volatility == null) return const Err('volatility');
    final levels = decoded['keyLevels'];
    if (levels is! List<Object?> || levels.any((l) => l is! String)) {
      return const Err('keyLevels');
    }
    final source = decoded['dataSource'];
    if (source is! String) return const Err('dataSource');
    final asOf = decoded['dataAsOf'];
    final parsedAsOf = asOf is String ? DateTime.tryParse(asOf) : null;
    if (parsedAsOf == null) return const Err('dataAsOf');
    final keyLevels = levels.cast<String>();
    return Ok(
      MoveStructure(
        trend: trend,
        volatility: volatility,
        keyLevels: keyLevels.length <= maxKeyLevels
            ? keyLevels
            : keyLevels.sublist(0, maxKeyLevels),
        dataSource: source,
        dataAsOf: parsedAsOf.toUtc(),
      ),
    );
  }

  static T? _enum<T extends Enum>(List<T> values, Object? raw) {
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is MoveStructure &&
      other.trend == trend &&
      other.volatility == volatility &&
      other.keyLevels.length == keyLevels.length &&
      other.keyLevels.asMap().entries.every(
        (e) => keyLevels[e.key] == e.value,
      ) &&
      other.dataSource == dataSource &&
      other.dataAsOf == dataAsOf;

  @override
  int get hashCode => Object.hash(
    trend,
    volatility,
    Object.hashAll(keyLevels),
    dataSource,
    dataAsOf,
  );
}
