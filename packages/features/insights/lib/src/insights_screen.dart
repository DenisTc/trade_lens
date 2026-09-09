import 'package:domain/domain.dart';
import 'package:features_insights/src/insights_model.dart';
import 'package:features_insights/src/ticker_card.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sdui/sdui.dart';

/// Server-driven screen: nodes from Remote Config rendered by `sdui`, the
/// ticker card bound to live quotes, buttons routed through the host's
/// allowlist.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({
    required this.onRoute,
    required this.allowedRoutes,
    super.key,
  });

  /// Navigates to an allowed in-app route (go_router in the app).
  final void Function(String route) onRoute;

  /// go_router patterns a config button may open, e.g. `/p/:symbol`.
  final List<String> allowedRoutes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(insightsModelProvider);
    final theme = Theme.of(context);
    final t = context.tokens;
    return Scaffold(
      body: Column(
        children: [
          ScreenHeader(
            title: l10n.tabInsights,
            actions: [
              if (state.value case final s?)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Tooltip(
                    message: s.origin == InsightsConfigOrigin.remote
                        ? l10n.insightsConfigRemote
                        : l10n.insightsConfigDefaults,
                    child: StatusChip(
                      key: Key('insights_origin_${s.origin.name}'),
                      label: s.origin == InsightsConfigOrigin.remote
                          ? 'Remote Config'
                          : 'Built-in',
                      color: s.origin == InsightsConfigOrigin.remote
                          ? t.up
                          : t.muted,
                      active: s.origin == InsightsConfigOrigin.remote,
                    ),
                  ),
                ),
            ],
          ),
          Expanded(
            child: AsyncValueView<InsightsState>(
              value: state,
              loading: () => ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                children: const [
                  Skeleton(width: 180, height: 22),
                  SizedBox(height: 14),
                  Skeleton(),
                  SizedBox(height: 8),
                  Skeleton(width: 240),
                  SizedBox(height: 20),
                  Skeleton(height: 84, radius: 14),
                  SizedBox(height: 12),
                  Skeleton(height: 84, radius: 14),
                ],
              ),
              error: (error, _) => ErrorView(
                error: error,
                onRetry: () => ref.invalidate(insightsModelProvider),
              ),
              data: (s) => SduiRenderer(
                screen: s.screen,
                languageCode: Localizations.localeOf(context).languageCode,
                padding: EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  MediaQuery.paddingOf(context).bottom + 24,
                ),
                host: SduiHost(
                  allowlist: SduiRouteAllowlist(allowedRoutes),
                  onRoute: onRoute,
                  tickerCard: (context, node) => TickerCard(
                    symbol: node.symbol,
                    showSparkline: node.showSparkline,
                    onTap: () => onRoute('/p/${node.symbol}'),
                  ),
                ),
              ),
            ),
          ),
          if (state.hasError)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('${state.error}', style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
