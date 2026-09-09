import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom navigation over the three top-level branches. go_router's
/// StatefulShellRoute keeps each tab's stack alive.
class HomeShell extends StatelessWidget {
  const HomeShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.show_chart),
            label: l10n.tabMarkets,
          ),
          NavigationDestination(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: l10n.tabPortfolio,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            label: l10n.tabSettings,
          ),
        ],
      ),
    );
  }
}
