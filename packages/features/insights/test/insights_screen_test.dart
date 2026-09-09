import 'dart:async';

import 'package:domain/domain.dart';
import 'package:features_insights/features_insights.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdui/sdui.dart';

void main() {
  const remote = InsightsConfig(
    insightsScreenJson:
        '{"schema":1,"children":[ '
        '{"type":"header","text":{"en":"Market today","ru":"Рынок сегодня"}}, '
        '{"type":"ticker_card","symbol":"BTCUSDT"}, '
        '{"type":"button","label":{"en":"Open BTC"},"action":{"route":"/p/BTCUSDT"}}, '
        '{"type":"button","label":{"en":"Leave"},"action":{"route":"https://x.y"}} '
        ']}',
    aiInsightsEnabled: true,
    source: InsightsConfigOrigin.remote,
  );

  late FakeMarketDataSource source;
  late FakeInsightsConfigSource config;
  late RecordingErrorReporter reporter;
  final routes = <String>[];

  Widget app({Locale locale = const Locale('en')}) => testApp(
    locale: locale,
    overrides: fakeOverrides(
      source: source,
      config: config,
      errorReporter: reporter,
    ),
    home: InsightsScreen(
      onRoute: routes.add,
      allowedRoutes: const ['/', '/p/:symbol', '/portfolio'],
    ),
  );

  /// Pumps until [finder] matches; the asset fallback needs a few turns.
  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  setUp(() {
    source = FakeMarketDataSource();
    config = FakeInsightsConfigSource(remote);
    reporter = RecordingErrorReporter();
    routes.clear();
  });

  testWidgets('renders the remote screen with a live ticker card', (
    tester,
  ) async {
    await tester.pumpWidget(app(locale: const Locale('ru')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Рынок сегодня'), findsOneWidget);
    expect(find.byKey(const Key('insights_origin_remote')), findsOneWidget);
    expect(find.byKey(const Key('ticker_card_BTCUSDT')), findsOneWidget);

    final btc = source.instrumentFor(defaultAssets.first, 'USDT');
    source.emit(btc, '78339.52', change: '-1.939');
    await tester.pump();
    expect(find.text('78\u00a0339,52'), findsOneWidget);

    await tester.tap(find.text('Open BTC'));
    expect(routes, ['/p/BTCUSDT']);

    await tester.tap(find.byKey(const Key('ticker_card_BTCUSDT')));
    expect(routes, ['/p/BTCUSDT', '/p/BTCUSDT']);

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('sdui_button_https://x.y')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('a broken update keeps the last valid screen and reports', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();
    expect(find.text('Market today'), findsOneWidget);

    config.push(
      const InsightsConfig(
        insightsScreenJson: '{"schema":1,"children":[{"type":"button"}]}',
        aiInsightsEnabled: true,
        source: InsightsConfigOrigin.remote,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Market today'), findsOneWidget);
    expect(reporter.reports, hasLength(1));
    expect(reporter.reports.single.$1, isA<SduiParseError>());
    expect(reporter.reports.single.$2, contains('insights_screen'));
  });

  testWidgets('a newer schema is refused like any other bad config', (
    tester,
  ) async {
    config = FakeInsightsConfigSource(
      const InsightsConfig(
        insightsScreenJson:
            '{"schema":${sduiSupportedSchema + 1},"children":[]}',
        aiInsightsEnabled: false,
        source: InsightsConfigOrigin.remote,
      ),
    );
    await tester.pumpWidget(app());
    await pumpUntil(tester, find.byKey(const Key('insights_origin_defaults')));
    expect(find.byKey(const Key('insights_origin_defaults')), findsOneWidget);
    expect(reporter.reports.single.$1.toString(), contains('newer'));
  });

  testWidgets('a broken first config falls back to the bundled default', (
    tester,
  ) async {
    config = FakeInsightsConfigSource(
      const InsightsConfig(
        insightsScreenJson: 'not json',
        aiInsightsEnabled: false,
        source: InsightsConfigOrigin.remote,
      ),
    );
    await tester.pumpWidget(app());
    await pumpUntil(tester, find.byKey(const Key('insights_origin_defaults')));

    expect(find.byKey(const Key('insights_origin_defaults')), findsOneWidget);
    expect(find.text('Market today'), findsOneWidget);
    expect(find.byKey(const Key('ticker_card_BTCUSDT')), findsOneWidget);
    expect(reporter.reports, hasLength(1));
  });

  testWidgets('an unknown symbol renders as not available', (tester) async {
    config = FakeInsightsConfigSource(
      const InsightsConfig(
        insightsScreenJson: '{"schema":1,"children":[{"type":"ticker_card","symbol":"NOPEUSDT"}]}',
        aiInsightsEnabled: false,
        source: InsightsConfigOrigin.remote,
      ),
    );
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('NOPEUSDT is not available'), findsOneWidget);
  });

  testWidgets('a mistyped field after a valid config keeps the screen', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();
    config.push(
      const InsightsConfig(
        insightsScreenJson: '{"schema":1,"children":[{"type":"ticker_card","symbol":"BTCUSDT","showSparkline":"no"}]}',
        aiInsightsEnabled: true,
        source: InsightsConfigOrigin.remote,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Market today'), findsOneWidget);
    expect(find.byKey(const Key('insights_origin_remote')), findsOneWidget);
    expect(reporter.reports, hasLength(1));
  });

  testWidgets('a newer schema after a valid config shows the bundled screen', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('insights_origin_remote')), findsOneWidget);
    config.push(
      const InsightsConfig(
        insightsScreenJson:
            '{"schema":${sduiSupportedSchema + 1},"children":[]}',
        aiInsightsEnabled: true,
        source: InsightsConfigOrigin.remote,
      ),
    );
    await pumpUntil(tester, find.byKey(const Key('insights_origin_defaults')));
    expect(find.byKey(const Key('insights_origin_defaults')), findsOneWidget);
    expect(find.text('About this screen'), findsOneWidget);
  });

  testWidgets('a valid config arriving while the fallback loads wins', (
    tester,
  ) async {
    final gate = Completer<String>();
    config = FakeInsightsConfigSource(
      const InsightsConfig(
        insightsScreenJson: 'broken',
        aiInsightsEnabled: false,
        source: InsightsConfigOrigin.remote,
      ),
    );
    await tester.pumpWidget(
      testApp(
        overrides: [
          ...fakeOverrides(
            source: source,
            config: config,
            errorReporter: reporter,
          ),
          insightsDefaultLoaderProvider.overrideWithValue(() => gate.future),
        ],
        home: InsightsScreen(onRoute: routes.add, allowedRoutes: const ['/']),
      ),
    );
    await tester.pump();
    await tester.pump();
    config.push(remote);
    await tester.pump();
    await tester.pump();
    expect(find.text('Market today'), findsOneWidget);
    gate.complete('{"schema":1,"children":[{"type":"header","text":"Late"}]}');
    await tester.pump();
    await tester.pump();
    expect(find.text('Market today'), findsOneWidget);
    expect(find.text('Late'), findsNothing);
  });

  testWidgets('the last valid screen survives leaving and re-entering', (
    tester,
  ) async {
    final overrides = fakeOverrides(
      source: source,
      config: config,
      errorReporter: reporter,
    );
    Widget shell({required bool showInsights}) => testApp(
      overrides: overrides,
      home: showInsights
          ? InsightsScreen(onRoute: routes.add, allowedRoutes: const ['/'])
          : const Scaffold(body: Text('elsewhere')),
    );
    await tester.pumpWidget(shell(showInsights: true));
    await tester.pump();
    await tester.pump();
    expect(find.text('Market today'), findsOneWidget);
    config.push(
      const InsightsConfig(
        insightsScreenJson: 'broken',
        aiInsightsEnabled: false,
        source: InsightsConfigOrigin.remote,
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(shell(showInsights: false));
    await tester.pump();
    await tester.pumpWidget(shell(showInsights: true));
    await tester.pump();
    await tester.pump();
    expect(find.text('Market today'), findsOneWidget);
    expect(find.byKey(const Key('insights_origin_remote')), findsOneWidget);
  });
}
