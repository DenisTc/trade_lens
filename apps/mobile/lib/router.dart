import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tradelens/screens/markets_screen.dart';
import 'package:tradelens/screens/pair_screen.dart';

part 'router.g.dart';

/// Route paths are the single source of truth for deep links (`/p/{symbol}`),
/// SDUI button actions and in-app navigation.
abstract final class AppRoutes {
  static const markets = '/';
  static const pair = '/p/:symbol';

  static String pairPath(String symbol) => '/p/$symbol';
}

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) => GoRouter(
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
  errorBuilder: (context, state) =>
      Scaffold(body: Center(child: Text('Not found: ${state.uri}'))),
);
