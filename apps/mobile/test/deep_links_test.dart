import 'dart:async';

import 'package:features_shared/features_shared.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelens/app.dart';
import 'package:tradelens/deep_links.dart';
import 'package:tradelens/di/deep_link_lifecycle.dart';

void main() {
  group('routeFor', () {
    test('custom scheme opens the pair, the tabs and the markets list', () {
      expect(
        DeepLinks.routeFor(Uri.parse('tradelens://p/BTCUSDT')),
        '/p/BTCUSDT',
      );
      expect(
        DeepLinks.routeFor(Uri.parse('tradelens://portfolio')),
        '/portfolio',
      );
      expect(
        DeepLinks.routeFor(Uri.parse('tradelens://insights')),
        '/insights',
      );
    });

    test('https links are accepted under the Pages base path', () {
      expect(
        DeepLinks.routeFor(
          Uri.parse('https://denistc.github.io/trade_lens/p/ETHUSDT'),
        ),
        '/p/ETHUSDT',
      );
      expect(
        DeepLinks.routeFor(Uri.parse('https://denistc.github.io/trade_lens/')),
        '/',
      );
      expect(
        DeepLinks.routeFor(Uri.parse('https://denistc.github.io/trade_lens')),
        '/',
      );
      expect(
        DeepLinks.routeFor(
          Uri.parse('https://denistc.github.io/trade_lens/portfolio/'),
        ),
        '/portfolio',
      );
    });

    test('the query string never reaches the route', () {
      expect(
        DeepLinks.routeFor(
          Uri.parse('tradelens://p/BTCUSDT?next=/settings/ai&src=mail'),
        ),
        '/p/BTCUSDT',
      );
    });

    test('a strange authority is refused', () {
      for (final link in [
        // Credentials and ports have no business in a route link.
        'https://user:pass@denistc.github.io/trade_lens/p/BTCUSDT',
        'https://denistc.github.io:8443/trade_lens/p/BTCUSDT',
        'tradelens://p:8080/BTCUSDT',
        // A doubled separator must not normalise into a valid route.
        'https://denistc.github.io/trade_lens//',
        'https://denistc.github.io/trade_lens//p/BTCUSDT',
        'tradelens://p//BTCUSDT',
        // A look-alike host.
        'https://denistc.github.io.evil.example/trade_lens/p/BTCUSDT',
      ]) {
        expect(DeepLinks.routeFor(Uri.parse(link)), isNull, reason: link);
      }
    });

    test('percent-encoded separators do not build a route', () {
      for (final link in [
        'https://denistc.github.io/trade_lens/%2E%2E/settings/ai',
        'tradelens://p/BTC%2FUSDT/x',
        'tradelens://%73ettings/ai',
      ]) {
        expect(DeepLinks.routeFor(Uri.parse(link)), isNot('/settings/ai'));
      }
    });

    test('anything outside the allowlist is refused', () {
      for (final link in [
        // Another host serving the same paths.
        'https://evil.example/trade_lens/p/BTCUSDT',
        // Our host, but outside the app's base path.
        'https://denistc.github.io/other/p/BTCUSDT',
        'https://denistc.github.io/trade_lens/../secrets',
        // Sub-screens are not open from outside: a link must not drop
        // the user straight into the API-key screen.
        'tradelens://settings/ai',
        'tradelens://settings/source',
        'https://denistc.github.io/trade_lens/settings/ai',
        // Malformed pair segments.
        'tradelens://p/',
        'tradelens://p/BTC/USDT',
        // Other schemes and shapes.
        'http://denistc.github.io/trade_lens/p/BTCUSDT',
        'javascript:alert(1)',
        'tradelens://',
      ]) {
        expect(DeepLinks.routeFor(Uri.parse(link)), isNull, reason: link);
      }
    });

    test('pairLink builds the link the README and QR codes share', () {
      expect(
        DeepLinks.pairLink('BTCUSDT').toString(),
        'https://denistc.github.io/trade_lens/p/BTCUSDT',
      );
      expect(DeepLinks.routeFor(DeepLinks.pairLink('BTCUSDT')), '/p/BTCUSDT');
    });
  });

  group('DeepLinkLifecycle', () {
    late FakeMarketDataSource source;
    late StreamController<Uri> links;

    setUp(() {
      source = FakeMarketDataSource();
      links = StreamController<Uri>.broadcast();
    });

    tearDown(() => links.close());

    Widget app() => ProviderScope(
      retry: noRetry,
      overrides: fakeOverrides(source: source),
      child: DeepLinkLifecycle(
        links: links.stream,
        child: const TradeLensApp(),
      ),
    );

    testWidgets('a link opens the pair screen', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();
      expect(find.widgetWithText(AppBar, 'ETH/USDT'), findsNothing);

      links.add(Uri.parse('tradelens://p/ETHUSDT'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.widgetWithText(AppBar, 'ETH/USDT'), findsOneWidget);
    });

    testWidgets('the link the app was launched with opens on the first frame', (
      tester,
    ) async {
      // A launch link is replayed to the first subscriber, before any
      // frame is drawn.
      await tester.pumpWidget(
        ProviderScope(
          retry: noRetry,
          overrides: fakeOverrides(source: source),
          child: DeepLinkLifecycle(
            links: Stream.value(Uri.parse('tradelens://p/ETHUSDT')),
            child: const TradeLensApp(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.widgetWithText(AppBar, 'ETH/USDT'), findsOneWidget);
    });

    testWidgets('a stream error does not take the app down', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();

      links.addError(StateError('platform channel died'));
      await tester.pump();
      links.add(Uri.parse('tradelens://p/ETHUSDT'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(AppBar, 'ETH/USDT'), findsOneWidget);
    });

    testWidgets('a link after the widget is gone is ignored', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      links.add(Uri.parse('tradelens://p/ETHUSDT'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('a foreign link leaves the app where it was', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();

      links.add(Uri.parse('https://evil.example/trade_lens/p/ETHUSDT'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('BTC/USDT'), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'ETH/USDT'), findsNothing);
    });
  });
}
