import 'package:meta/meta.dart';

/// Schema version this package understands. A newer schema is refused so
/// the host falls back to its default screen; an older one still renders.
const sduiSupportedSchema = 1;

/// Text keyed by language code; `en` is the fallback.
@immutable
final class LocalizedText {
  const LocalizedText(this.values);

  final Map<String, String> values;

  String resolve(String languageCode) =>
      values[languageCode] ?? values['en'] ?? values.values.firstOrNull ?? '';

  @override
  bool operator ==(Object other) =>
      other is LocalizedText &&
      other.values.length == values.length &&
      other.values.entries.every((e) => values[e.key] == e.value);

  @override
  int get hashCode =>
      Object.hashAll(values.entries.map((e) => '${e.key}=${e.value}'));

  @override
  String toString() => 'LocalizedText($values)';
}

/// What a button does. Only in-app routes; arbitrary URLs never come from
/// the config (spec: white-listed go_router routes).
@immutable
final class SduiAction {
  const SduiAction({required this.route});

  final String route;

  @override
  bool operator ==(Object other) => other is SduiAction && other.route == route;

  @override
  int get hashCode => route.hashCode;
}

enum SduiTextStyle { body, muted }

/// One node of the screen tree. Exactly the five spec types plus
/// [SduiUnknown] for forward compatibility.
@immutable
sealed class SduiNode {
  const SduiNode();
}

final class SduiHeader extends SduiNode {
  const SduiHeader({required this.text});

  final LocalizedText text;
}

final class SduiText extends SduiNode {
  const SduiText({required this.text, this.style = SduiTextStyle.body});

  final LocalizedText text;
  final SduiTextStyle style;
}

final class SduiTickerCard extends SduiNode {
  const SduiTickerCard({required this.symbol, this.showSparkline = true});

  /// Instrument symbol as the sources use it, e.g. `BTCUSDT`.
  final String symbol;
  final bool showSparkline;
}

final class SduiButton extends SduiNode {
  const SduiButton({required this.label, required this.action});

  final LocalizedText label;
  final SduiAction action;
}

final class SduiList extends SduiNode {
  const SduiList({required this.children});

  final List<SduiNode> children;
}

/// A type this version does not know: a grey placeholder in debug, empty
/// space in release.
final class SduiUnknown extends SduiNode {
  const SduiUnknown({required this.type});

  final String type;
}

@immutable
final class SduiScreen {
  const SduiScreen({required this.schema, required this.children});

  final int schema;
  final List<SduiNode> children;
}
