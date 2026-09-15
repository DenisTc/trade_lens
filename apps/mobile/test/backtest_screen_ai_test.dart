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
                onDeviceLlm: _AvailabilityLlm(availability),
                config: FakeInsightsConfigSource(
                  const InsightsConfig(
                    insightsScreenJson: '{"schema":1,"children":[]}',
                    aiInsightsEnabled: false,
                    source: InsightsConfigOrigin.remote,
                  ),
                ),
              ),
              appLanguageCodeProvider.overrideWithValue('en'),
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

final class _AvailabilityLlm implements OnDeviceLlmApi {
  const _AvailabilityLlm(this.status);

  final OnDeviceAvailability status;

  @override
  Future<OnDeviceAvailability> availability(String languageCode) async =>
      status;

  @override
  Future<void> cancel() async {}

  @override
  Future<String> generate({
    required String system,
    required String prompt,
    required String languageCode,
    required int maxOutputChars,
  }) async => 'unused';

  @override
  Future<String> runtimeName() async => 'fake';
}
