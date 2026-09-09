@Tags(['golden'])
library;

import 'dart:io';

import 'package:domain/domain.dart';
import 'package:features_insights/features_insights.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The spec's fixture-to-screen check: the sdui test fixture rendered by
/// the real Insights screen, light and dark. Regenerate with
/// `flutter test --update-goldens --tags golden`.
void main() {
  final fixture = File('../../sdui/test/fixtures/insights_v1.json')
      .readAsStringSync();

  for (final brightness in Brightness.values) {
    testWidgets('insights screen · ${brightness.name}', (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final source = FakeMarketDataSource();
      await tester.pumpWidget(
        testApp(
          brightness: brightness,
          overrides: fakeOverrides(
            source: source,
            config: FakeInsightsConfigSource(
              InsightsConfig(
                insightsScreenJson: fixture,
                aiInsightsEnabled: false,
                source: InsightsConfigOrigin.remote,
              ),
            ),
          ),
          home: InsightsScreen(
            onRoute: (_) {},
            allowedRoutes: const ['/p/:symbol'],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final btc = source.instrumentFor(defaultAssets.first, 'USDT');
      final eth = source.instrumentFor(defaultAssets[1], 'USDT');
      source
        ..emit(btc, '67432.10', change: '2.14')
        ..emit(eth, '3518.42', change: '-1.36');
      await tester.pump();
      await expectLater(
        find.byType(InsightsScreen),
        matchesGoldenFile('goldens/insights_screen_${brightness.name}.png'),
      );
    });
  }
}
