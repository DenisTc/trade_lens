import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Floating glass tab bar over the three top-level branches. go_router's
/// StatefulShellRoute keeps each tab's stack alive; `extendBody` lets
/// lists scroll under the bar while their bottom padding ends above it.
class HomeShell extends StatelessWidget {
  const HomeShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: GlassTabBar(
        selectedIndex: navigationShell.currentIndex,
        onSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        tabs: [
          GlassTab(
            key: const Key('tab_markets'),
            icon: Icons.candlestick_chart_outlined,
            label: l10n.tabMarkets,
          ),
          GlassTab(
            key: const Key('tab_portfolio'),
            icon: Icons.pie_chart_outline,
            label: l10n.tabPortfolio,
          ),
          GlassTab(
            key: const Key('tab_settings'),
            icon: Icons.tune,
            label: l10n.tabSettings,
          ),
        ],
      ),
    );
  }
}
