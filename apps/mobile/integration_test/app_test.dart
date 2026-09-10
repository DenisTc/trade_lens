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
void main() {
  patrolTest(
    'markets → pair → chart, then a position shows up valued in the portfolio',
    ($) async {
      await app.main();
      await $.pump();

      // The catalog arrives over the network; the rows are the first
      // thing a user sees.
      await $(markets.PairTile).waitUntilVisible(timeout: _long);
      await $('BTC/USDT').waitUntilVisible(timeout: _long);

      await $('BTC/USDT').tap();
      await $(#pair_chart).waitUntilVisible(timeout: _long);
      // The pills row is a full-width Row, so its own centre can fall in
      // the empty space past the last pill: the pill is what has to be
      // on screen.
      await $(#interval_selector).$(InkWell).first.waitUntilVisible();

      // The tab bar stays put over the pair screen: it lives in the
      // shell, so the portfolio is one tap away.
      await $(#tab_portfolio).tap();
      await $(#add_position).waitUntilVisible(timeout: _long);

      // A device keeps its portfolio between runs, so the scenario starts
      // from an empty one — which also exercises swipe-to-delete.
      await _clearPortfolio($);
      await $(#add_position).tap();

      await $(#position_qty).waitUntilVisible();
      await $(#position_qty).enterText('0.5');
      await $(#position_price).enterText('60000');
      await $(#position_save).tap();

      // The row is valued at the live price, so only its shape is
      // asserted: the empty state is gone and the total is no longer the
      // dash an empty portfolio shows.
      await _until(
        $,
        () =>
            !$(#portfolio_empty).exists &&
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
    await $(#tab_settings).tap();
    await $(#settings_source).waitUntilVisible();
    await $(#settings_source).tap();

    await $(#source_coingecko).waitUntilVisible();
    await $(#source_coingecko).tap();

    await $(#tab_markets).tap();
    await $(markets.PairTile).waitUntilVisible(timeout: _long);
    await $(markets.PairTile).first.tap();

    // CoinGecko serves prices only: no interval pills, no order book,
    // and the screen says which candles it is drawing.
    await $(#prices_only_note).waitUntilVisible(timeout: _long);
    expect($(#interval_selector).exists, isFalse);
    expect($(#order_book_bids).exists, isFalse);

    // The choice is persisted, and the app is not reinstalled between
    // runs: leave the source as the suite found it.
    await $(#tab_settings).tap();
    // The settings tab restored its own stack, so it reopened on the
    // source screen; tapping the selected tab pops back to its root.
    await $(#tab_settings).tap();
    await $(#settings_source).tap();
    await $(#source_auto).tap();
  });
}

/// Enough for a cold start plus a network round trip on a CI device.
const _long = Duration(seconds: 60);

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

/// Swipes away every position, so the run starts from a known portfolio.
Future<void> _clearPortfolio(PatrolIntegrationTester $) async {
  while ($(Dismissible).exists) {
    await $.tester.drag($(Dismissible).first, const Offset(-400, 0));
    await $.pump(const Duration(milliseconds: 600));
  }
  await _until($, () => $(#portfolio_empty).exists);
}
