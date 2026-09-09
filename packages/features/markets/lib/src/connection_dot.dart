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
    final tokens = context.tokens;
    final l10n = context.l10n;
    final (color, label) = switch (status) {
      ConnectionStatus.connected => (tokens.up, l10n.connectionConnected),
      ConnectionStatus.connecting => (tokens.warn, l10n.connectionConnecting),
      ConnectionStatus.reconnecting => (
        tokens.warn,
        l10n.connectionReconnecting,
      ),
      ConnectionStatus.suspended => (tokens.muted, l10n.connectionSuspended),
      ConnectionStatus.idle => (tokens.muted, l10n.connectionIdle),
    };
    return Tooltip(
      message: label,
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
