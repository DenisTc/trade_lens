import 'package:features_markets/features_markets.dart' as markets;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:tradelens/main.dart' as app;

/// The two end-to-end scenarios from the spec, run by `patrol test` on a
/// real device against the live data stack.
///
/// Nothing here asserts a price: the numbers move. The scenarios assert
/// the parts that must hold whichever source answers — that a pair opens,
/// that a position is valued, and that the REST-only source hides what it
/// cannot serve.
///
/// Each scenario establishes what it needs at the start instead of tidying
/// up at the end: a device keeps its data between runs, and a run that
/// fails half-way through never gets to its own cleanup.
void main() {
  patrolTest(
    'markets → pair → chart, then a position shows up valued in the portfolio',
    ($) async {
      await app.main();
      await $.pump();

      // The catalog arrives over the network; the rows are the first
      // thing a user sees.
      await $(markets.PairTile).waitUntilVisible(timeout: _long);
      await _chooseSource($, #source_auto);

      // The quote depends on which source the region resolved to, so the
      // pair is matched by its base asset.
      final btc = find.textContaining('BTC/');
      await $(btc).waitUntilVisible(timeout: _long);
      await $(btc).tap();
      await $(#pair_chart).waitUntilVisible(timeout: _long);

      // The tab bar stays put over the pair screen: it lives in the
      // shell, so the portfolio is one tap away.
      await $(#tab_portfolio).tap();
      await $(#add_position).waitUntilVisible(timeout: _long);

      // Starting from an empty portfolio is what makes the assertion
      // below mean something; it also exercises swipe-to-delete.
      await _clearPortfolio($);
      await $(#add_position).tap();

      await $(#position_qty).waitUntilVisible();
      await $(#position_qty).enterText('0.5');
      await $(#position_price).enterText('60000');
      await $(#position_save).tap();

      // The row is valued at the live price, so only its shape is
      // asserted: the empty state is gone, the total is no longer the
      // dash an empty portfolio shows, and the PnL against the 60000
      // entry is there next to it.
      final pnl = find.byWidgetPredicate(
        (w) => w.key.toString().contains('portfolio_pnl_'),
        description: 'the portfolio PnL chip',
      );
      await _until(
        $,
        () =>
            !$(#portfolio_empty).exists &&
            $(pnl).exists &&
            $(#portfolio_total).exists &&
            $(#portfolio_total).text != '—',
      );
    },
  );

  patrolTest('the REST-only source hides the order book and says so', (
    $,
  ) async {
    await app.main();
    await $.pump();

    await $(markets.PairTile).waitUntilVisible(timeout: _long);
    await _chooseSource($, #source_coingecko);

    await $(markets.PairTile).waitUntilVisible(timeout: _long);
    await $(markets.PairTile).first.tap();

    // CoinGecko serves prices only: the chart draws (the key is on the
    // chart itself, so candles did arrive), the screen says which candles
    // those are, and neither the pills nor the book are built. The
    // presence of both for a full source is a widget test —
    // `pair_screen_test.dart`.
    await $(#pair_chart).waitUntilVisible(timeout: _long);
    await $(#prices_only_note).waitUntilVisible(timeout: _long);
    expect($(#interval_selector).exists, isFalse);
    expect($(markets.OrderBookView).exists, isFalse);
  });
}

/// Enough for a cold start plus a network round trip on a CI device.
const _long = Duration(seconds: 60);

/// Picks a data source in Settings and comes back to the markets tab.
Future<void> _chooseSource(PatrolIntegrationTester $, Symbol source) async {
  await $(#tab_settings).tap();
  // The settings tab keeps its own stack, so it can reopen on a screen a
  // previous run left it on; tapping the selected tab pops to its root.
  await $(#tab_settings).tap();
  await $(#settings_source).tap();
  await $(source).tap();
  await $(#tab_markets).tap();
}

/// Swipes away every position, so the run starts from a known portfolio.
Future<void> _clearPortfolio(PatrolIntegrationTester $) async {
  while ($(Dismissible).exists) {
    await $.tester.drag($(Dismissible).first, const Offset(-400, 0));
    await $.pump(const Duration(milliseconds: 600));
  }
  await _until($, () => $(#portfolio_empty).exists);
}

/// Pumps until [ready] holds, because what we are waiting for is a value
/// arriving over the network rather than a widget appearing.
Future<void> _until(
  PatrolIntegrationTester $,
  bool Function() ready, {
  Duration timeout = _long,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('the condition still did not hold after $timeout');
    }
    await $.pump(const Duration(milliseconds: 250));
  }
}
