import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sdui/src/model.dart';
import 'package:sdui/src/route_allowlist.dart';

/// What the host supplies: the one node that needs live data and the way
/// to navigate. Everything else renders from the theme.
@immutable
final class SduiHost {
  const SduiHost({
    required this.tickerCard,
    required this.onRoute,
    required this.allowlist,
  });

  final Widget Function(BuildContext context, SduiTickerCard node) tickerCard;

  /// Called only for routes the [allowlist] accepts.
  final void Function(String route) onRoute;
  final SduiRouteAllowlist allowlist;
}

/// Renders a parsed screen as a vertical list of nodes.
class SduiRenderer extends StatelessWidget {
  const SduiRenderer({
    required this.screen,
    required this.languageCode,
    required this.host,
    super.key,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 24),
  });

  final SduiScreen screen;
  final String languageCode;
  final SduiHost host;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('sdui_screen'),
    padding: padding,
    children: [
      for (final node in screen.children)
        SduiNodeView(node: node, languageCode: languageCode, host: host),
    ],
  );
}

/// One node; lists recurse.
class SduiNodeView extends StatelessWidget {
  const SduiNodeView({
    required this.node,
    required this.languageCode,
    required this.host,
    super.key,
  });

  final SduiNode node;
  final String languageCode;
  final SduiHost host;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (node) {
      SduiHeader(:final text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
        child: Text(
          text.resolve(languageCode),
          style: theme.textTheme.titleLarge,
        ),
      ),
      SduiText(:final text, :final style) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          text.resolve(languageCode),
          style: style == SduiTextStyle.muted
              ? theme.textTheme.bodySmall?.copyWith(height: 1.5)
              : theme.textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
      ),
      SduiTickerCard() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: host.tickerCard(context, node as SduiTickerCard),
      ),
      SduiButton(:final label, :final action) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: FilledButton(
          key: Key('sdui_button_${action.route}'),
          onPressed: host.allowlist.allows(action.route)
              ? () => host.onRoute(action.route)
              : null,
          child: Text(label.resolve(languageCode)),
        ),
      ),
      SduiList(:final children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in children)
            SduiNodeView(node: child, languageCode: languageCode, host: host),
        ],
      ),
      SduiUnknown(:final type) => SduiUnknownView(type: type),
    };
  }
}

/// Grey box naming the type in debug builds, nothing in release.
class SduiUnknownView extends StatelessWidget {
  const SduiUnknownView({required this.type, super.key});

  final String type;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: Key('sdui_unknown_$type'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'unknown node: $type',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
