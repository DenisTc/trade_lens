import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Socket state in the header as a lens ring with a word: filled green
/// "Live", amber while (re)connecting, empty grey otherwise.
class ConnectionDot extends ConsumerWidget {
  const ConnectionDot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status =
        ref.watch(connectionStatusProvider).value ?? ConnectionStatus.idle;
    final tokens = context.tokens;
    final l10n = context.l10n;
    final (color, label, active) = switch (status) {
      ConnectionStatus.connected => (tokens.up, l10n.connectionConnected, true),
      ConnectionStatus.connecting => (
        tokens.warn,
        l10n.connectionConnecting,
        false,
      ),
      ConnectionStatus.reconnecting => (
        tokens.warn,
        l10n.connectionReconnecting,
        false,
      ),
      ConnectionStatus.suspended => (
        tokens.muted,
        l10n.connectionSuspended,
        false,
      ),
      ConnectionStatus.idle => (tokens.muted, l10n.connectionIdle, false),
    };
    return Padding(
      key: ValueKey(status),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: StatusChip(
        label: status == ConnectionStatus.connected
            ? label
            : status == ConnectionStatus.idle ||
                  status == ConnectionStatus.suspended
            ? l10n.connectionOffline
            : label,
        color: color,
        active: active,
      ),
    );
  }
}
