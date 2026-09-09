import 'package:features_portfolio/features_portfolio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tradelens/screens/home_shell.dart';
import 'package:tradelens/screens/markets_screen.dart';
import 'package:tradelens/screens/pair_screen.dart';
import 'package:tradelens/screens/settings_screen.dart';

part 'router.g.dart';

/// Route paths are the single source of truth for deep links (`/p/{symbol}`),
/// SDUI button actions and in-app navigation.
abstract final class AppRoutes {
  static const markets = '/';
  static const pair = '/p/:symbol';
  static const portfolio = '/portfolio';
  static const settings = '/settings';

  static String pairPath(String symbol) => '/p/$symbol';
}

/// Start route for demos and screenshots, e.g.
/// `--dart-define=TL_INITIAL_ROUTE=/p/BTCUSDT`. Empty in normal builds.
const initialRouteOverride = String.fromEnvironment('TL_INITIAL_ROUTE');

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) => GoRouter(
  initialLocation: initialRouteOverride.isEmpty
      ? AppRoutes.markets
      : initialRouteOverride,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => HomeShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.markets,
              builder: (context, state) => const MarketsScreen(),
              routes: [
                GoRoute(
                  path: 'p/:symbol',
                  builder: (context, state) =>
                      PairScreen(symbol: state.pathParameters['symbol']!),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.portfolio,
              builder: (context, state) => const PortfolioScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.settings,
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) =>
      Scaffold(body: Center(child: Text('Not found: ${state.uri}'))),
);
