import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Socket state in the app bar: green connected, amber reconnecting,
/// grey otherwise. Tooltip names the state for accessibility.
class ConnectionDot extends ConsumerWidget {
  const ConnectionDot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status =
        ref.watch(connectionStatusProvider).value ?? ConnectionStatus.idle;
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      ConnectionStatus.connected => Colors.green,
      ConnectionStatus.connecting ||
      ConnectionStatus.reconnecting => Colors.amber,
      ConnectionStatus.idle || ConnectionStatus.suspended => scheme.outline,
    };
    return Tooltip(
      message: status.name,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          key: ValueKey(status),
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
