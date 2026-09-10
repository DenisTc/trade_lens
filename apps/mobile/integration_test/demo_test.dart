import 'package:features_markets/features_markets.dart' as markets;
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:tradelens/main.dart' as app;

/// The README demo, driven rather than filmed by hand.
///
/// `tooling/scripts/record_demo.sh` grabs simulator frames while this runs
/// and `docs/demo/build.py` turns them into the GIF, so the animation can
/// be rebuilt after a redesign instead of re-recorded.
///
/// The pauses are the point: every step holds long enough for a few
/// frames to land on it. Run it with `TL_AI_DEMO=true` (the summary
/// replays the bundled example, no key and no tokens spent) and
/// `TL_DEMO_PORTFOLIO=true` (a portfolio worth showing).
void main() {
  patrolTest('the demo walk-through', ($) async {
    await app.main();
    await $.pump();

    await $(markets.PairTile).waitUntilVisible(timeout: _long);
    await _hold($, 2);

    // Markets → the pair screen.
    final btc = find.textContaining('BTC/');
    await $(btc).waitUntilVisible(timeout: _long);
    await $(btc).tap();
    await $(#pair_chart).waitUntilVisible(timeout: _long);
    await _hold($, 2);

    // The crosshair: a long press on the chart, then a slow sweep left.
    final gesture = await $.tester.startGesture(
      $.tester.getCenter($(#pair_chart).finder),
    );
    await _hold($, 1);
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(-12, 4));
      await $.pump(const Duration(milliseconds: 110));
    }
    await _hold($, 1);
    await gesture.up();

    // The AI move summary, replayed from the recorded example.
    if ($(#move_summary).exists) {
      await $(#move_summary).tap();
      if ($(#ai_show_example).exists) await $(#ai_show_example).tap();
      await $(#ai_summary_text).waitUntilVisible(timeout: _long);
      await _hold($, 6);
      // The sheet is modal: a tap on the barrier above it closes it.
      await $.tester.tapAt(const Offset(30, 70));
      await _hold($, 1);
    }

    // The portfolio, valued on the live price.
    await $(#tab_portfolio).tap();
    await _hold($, 3);

    // The server-driven Insights screen.
    await $(#tab_insights).tap();
    await _hold($, 3);

    // And the light theme, from Settings → Appearance.
    await $(#tab_settings).tap();
    await $(#settings_appearance).tap();
    await $(#theme_light).tap();
    await _hold($, 2);
    await $(#tab_markets).tap();
    await _hold($, 3);

    // Back to dark, so a rerun starts where this one did. The settings
    // tab reopens on the screen it was left on; tapping the selected tab
    // pops it back to the root.
    await $(#tab_settings).tap();
    await $(#tab_settings).tap();
    await $(#settings_appearance).tap();
    await $(#theme_dark).tap();
  });
}

const _long = Duration(seconds: 60);

/// Holds the current screen long enough for the recorder to catch it.
Future<void> _hold(PatrolIntegrationTester $, int seconds) async {
  for (var i = 0; i < seconds * 4; i++) {
    await $.pump(const Duration(milliseconds: 250));
  }
}
