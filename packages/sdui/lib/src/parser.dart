import 'dart:convert';

import 'package:core/core.dart';
import 'package:meta/meta.dart';
import 'package:sdui/src/model.dart';

/// Why a config could not become a screen. The host keeps the last valid
/// screen and reports the error; nothing is rendered from a broken tree.
@immutable
final class SduiParseError {
  const SduiParseError(this.message, {this.path = r'$'});

  final String message;

  /// JSON path of the offending element, for the error report.
  final String path;

  @override
  bool operator ==(Object other) =>
      other is SduiParseError && other.message == message && other.path == path;

  @override
  int get hashCode => Object.hash(message, path);

  @override
  String toString() => 'SduiParseError($path: $message)';
}

/// JSON → [SduiScreen]. Strict about the five known types' fields (a
/// wrong type is an error, never a cast crash), lenient about unknown
/// types (kept as [SduiUnknown]) and unknown extra fields (ignored), so a
/// newer config degrades instead of failing. Budgets keep a hostile or
/// runaway config from stalling the UI: input length, nesting depth, node
/// count and text length.
abstract final class SduiParser {
  static const int maxInputLength = 256 * 1024;
  static const maxDepth = 8;
  static const maxNodes = 500;
  static const maxTextLength = 2000;

  static Result<SduiScreen, SduiParseError> parse(String json) {
    if (json.length > maxInputLength) {
      return const Err(
        SduiParseError('input longer than $maxInputLength characters'),
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      return Err(SduiParseError('invalid JSON: ${e.message}'));
    }
    return parseValue(decoded);
  }

  static Result<SduiScreen, SduiParseError> parseValue(Object? decoded) {
    return _Parse().screen(decoded);
  }
}

/// Whether [error] means the config is newer than this app understands
/// (as opposed to broken): the host shows its bundled screen for that.
bool isUnsupportedSchema(SduiParseError error) =>
    error.path == r'$.schema' && error.message.startsWith('schema ');

final class _Parse {
  int _nodes = 0;

  Result<SduiScreen, SduiParseError> screen(Object? decoded) {
    if (decoded is! Map<String, Object?>) {
      return const Err(SduiParseError('root must be an object'));
    }
    final schema = decoded['schema'];
    if (schema is! int) {
      return const Err(SduiParseError('missing int', path: r'$.schema'));
    }
    if (schema > sduiSupportedSchema) {
      return Err(
        SduiParseError(
          'schema $schema is newer than supported $sduiSupportedSchema',
          path: r'$.schema',
        ),
      );
    }
    final children = decoded['children'];
    if (children is! List<Object?>) {
      return const Err(SduiParseError('missing list', path: r'$.children'));
    }
    return _children(
      children,
      r'$.children',
      1,
    ).map((nodes) => SduiScreen(schema: schema, children: nodes));
  }

  Result<List<SduiNode>, SduiParseError> _children(
    List<Object?> raw,
    String path,
    int depth,
  ) {
    if (depth > SduiParser.maxDepth) {
      return Err(
        SduiParseError('nested deeper than ${SduiParser.maxDepth}', path: path),
      );
    }
    final nodes = <SduiNode>[];
    for (final (i, item) in raw.indexed) {
      if (++_nodes > SduiParser.maxNodes) {
        return Err(
          SduiParseError('more than ${SduiParser.maxNodes} nodes', path: path),
        );
      }
      final node = _node(item, '$path[$i]', depth);
      switch (node) {
        case Ok(:final value):
          nodes.add(value);
        case Err(:final error):
          return Err(error);
      }
    }
    return Ok(nodes);
  }

  Result<SduiNode, SduiParseError> _node(Object? raw, String path, int depth) {
    if (raw is! Map<String, Object?>) {
      return Err(SduiParseError('node must be an object', path: path));
    }
    final type = raw['type'];
    if (type is! String) {
      return Err(SduiParseError('missing string', path: '$path.type'));
    }
    switch (type) {
      case 'header':
        return _text(raw['text'], '$path.text').map((t) => SduiHeader(text: t));
      case 'text':
        final style = switch (raw['style']) {
          null || 'body' => SduiTextStyle.body,
          'muted' => SduiTextStyle.muted,
          _ => null,
        };
        if (style == null) {
          return Err(
            SduiParseError('must be body or muted', path: '$path.style'),
          );
        }
        return _text(
          raw['text'],
          '$path.text',
        ).map((t) => SduiText(text: t, style: style));
      case 'ticker_card':
        final symbol = raw['symbol'];
        if (symbol is! String || symbol.isEmpty) {
          return Err(SduiParseError('missing string', path: '$path.symbol'));
        }
        final showSparkline = raw['showSparkline'];
        if (showSparkline is! bool?) {
          return Err(
            SduiParseError('must be a boolean', path: '$path.showSparkline'),
          );
        }
        return Ok(
          SduiTickerCard(symbol: symbol, showSparkline: showSparkline ?? true),
        );
      case 'button':
        final action = raw['action'];
        final route = action is Map<String, Object?> ? action['route'] : null;
        if (route is! String || route.isEmpty) {
          return Err(
            SduiParseError('missing string', path: '$path.action.route'),
          );
        }
        return _text(raw['label'], '$path.label').map(
          (l) => SduiButton(
            label: l,
            action: SduiAction(route: route),
          ),
        );
      case 'list':
        final children = raw['children'];
        if (children is! List<Object?>) {
          return Err(SduiParseError('missing list', path: '$path.children'));
        }
        return _children(
          children,
          '$path.children',
          depth + 1,
        ).map((c) => SduiList(children: c));
      default:
        return Ok(SduiUnknown(type: type));
    }
  }

  Result<LocalizedText, SduiParseError> _text(Object? raw, String path) {
    if (raw is String) {
      return raw.length > SduiParser.maxTextLength
          ? Err(SduiParseError('text too long', path: path))
          : Ok(LocalizedText({'en': raw}));
    }
    if (raw is! Map<String, Object?> || raw.isEmpty) {
      return Err(SduiParseError('missing text', path: path));
    }
    final values = <String, String>{};
    for (final entry in raw.entries) {
      final v = entry.value;
      if (v is! String) {
        return Err(
          SduiParseError('must be a string', path: '$path.${entry.key}'),
        );
      }
      if (v.length > SduiParser.maxTextLength) {
        return Err(SduiParseError('text too long', path: '$path.${entry.key}'));
      }
      values[entry.key] = v;
    }
    return Ok(LocalizedText(values));
  }
}
