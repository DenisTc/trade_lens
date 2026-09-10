# Deep links

- [x] `DeepLinks.routeFor`: one validated mapper for `tradelens://…` and
      `https://denistc.github.io/trade_lens/…`, reusing the SDUI route
      allowlist; query and fragment dropped, credentials, ports and doubled
      separators refused
- [x] `DeepLinkLifecycle`: `app_links` subscription (launch link replayed),
      navigation through go_router, unknown links logged and ignored
- [x] iOS: custom scheme in Info.plist, `FlutterDeepLinkingEnabled=false`,
      `Runner.entitlements` with `applinks:` wired into Release only
- [x] Android: scheme and verified https intent filters,
      `flutter_deeplinking_enabled=false`
- [x] `docs/.well-known/{apple-app-site-association,assetlinks.json}`
- [x] Verified on the simulator: `xcrun simctl openurl booted
      "tradelens://p/ETHUSDT"` opens the pair
- [x] 23 tests in `apps/mobile`; Codex review, 6 findings fixed
- [ ] Open: publish the two files at the domain root (needs a
      `DenisTc.github.io` repo or a custom domain); add the release
      signing fingerprint; deferred deep links need AppsFlyer
