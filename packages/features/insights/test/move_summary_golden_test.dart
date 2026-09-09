@Tags(['golden'])
library;

import 'package:domain/domain.dart';
import 'package:features_insights/features_insights.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart' hide Interval;
import 'package:flutter_test/flutter_test.dart';

/// The summary sheet on the bundled example, light and dark. Regenerate
/// with `flutter test --update-goldens --tags golden`.
void main() {
  for (final brightness in Brightness.values) {
    testWidgets('move summary sheet · ${brightness.name}', (tester) async {
      tester.view
        ..physicalSize = const Size(390, 720)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final source = FakeMarketDataSource();
      final btc = source.instrumentFor(defaultAssets.first, 'USDT');
      await tester.pumpWidget(
        testApp(
          brightness: brightness,
          overrides: [
            ...fakeOverrides(source: source),
            demoClaudeTransportProvider.overrideWithValue(
              DemoClaudeTransport(delay: Duration.zero),
            ),
          ],
          home: Scaffold(body: MoveSummarySheet(instrument: btc)),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai_show_example')));
      for (var i = 0; i < 300; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      await expectLater(
        find.byType(MoveSummarySheet),
        matchesGoldenFile('goldens/move_summary_${brightness.name}.png'),
      );
    });
  }
}
