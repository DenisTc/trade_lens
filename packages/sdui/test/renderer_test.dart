import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdui/sdui.dart';

void main() {
  const screen = SduiScreen(
    schema: 1,
    children: [
      SduiHeader(text: LocalizedText({'en': 'Market today', 'ru': 'Рынок'})),
      SduiTickerCard(symbol: 'BTCUSDT'),
      SduiText(
        text: LocalizedText({'en': 'Quiet day'}),
        style: SduiTextStyle.muted,
      ),
      SduiButton(
        label: LocalizedText({'en': 'Open BTC'}),
        action: SduiAction(route: '/p/BTCUSDT'),
      ),
      SduiButton(
        label: LocalizedText({'en': 'Escape'}),
        action: SduiAction(route: 'https://evil.example'),
      ),
      SduiList(children: [SduiUnknown(type: 'surprise')]),
    ],
  );

  Widget host(String languageCode, List<String> routes) => MaterialApp(
    home: Scaffold(
      body: SduiRenderer(
        screen: screen,
        languageCode: languageCode,
        host: SduiHost(
          allowlist: SduiRouteAllowlist(['/p/:symbol']),
          onRoute: routes.add,
          tickerCard: (context, node) =>
              Text('card ${node.symbol}', key: Key('card_${node.symbol}')),
        ),
      ),
    ),
  );

  testWidgets('renders every node type in the requested language', (
    tester,
  ) async {
    final routes = <String>[];
    await tester.pumpWidget(host('ru', routes));
    expect(find.text('Рынок'), findsOneWidget);
    expect(find.byKey(const Key('card_BTCUSDT')), findsOneWidget);
    expect(find.text('Quiet day'), findsOneWidget);
    expect(find.byKey(const Key('sdui_unknown_surprise')), findsOneWidget);

    await tester.tap(find.text('Open BTC'));
    expect(routes, ['/p/BTCUSDT']);
  });

  testWidgets('a button with a route outside the allowlist is disabled', (
    tester,
  ) async {
    final routes = <String>[];
    await tester.pumpWidget(host('en', routes));
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('sdui_button_https://evil.example')),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.text('Escape'), warnIfMissed: false);
    expect(routes, isEmpty);
  });
}
