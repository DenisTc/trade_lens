import 'package:domain/domain.dart';
import 'package:features_backtest/features_backtest.dart';
import 'package:features_shared/features_shared.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelens/screens/backtest_screen.dart';

void main() {
  for (final (availability, hasExplainAction) in [
    (OnDeviceAvailability.available, true),
    (OnDeviceAvailability.unsupportedDevice, false),
  ]) {
    testWidgets(
      'disabled cloud with $availability has explain action: $hasExplainAction',
      (tester) async {
        await tester.pumpWidget(
          testApp(
            overrides: [
              ...fakeOverrides(
                source: FakeMarketDataSource(),
                config: FakeInsightsConfigSource(
                  const InsightsConfig(
                    insightsScreenJson: '{"schema":1,"children":[]}',
                    aiInsightsEnabled: false,
                    source: InsightsConfigOrigin.remote,
                  ),
                ),
              ),
              onDeviceAvailabilityProvider.overrideWith(
                (ref) async => availability,
              ),
            ],
            home: const BacktestRouteScreen(symbol: 'BTCUSDT'),
          ),
        );
        await tester.pump();
        await tester.pump();

        final screen = tester.widget<BacktestScreen>(
          find.byType(BacktestScreen),
        );
        expect(screen.onExplain, hasExplainAction ? isNotNull : isNull);
      },
    );
  }
}
