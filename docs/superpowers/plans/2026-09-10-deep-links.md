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
- [x] Both files served and valid at
      `https://denistc.github.io/trade_lens/.well-known/…`
- [ ] Open, and all about the https half: the platforms read them from the
      domain root, not from a project path (needs a `DenisTc.github.io`
      repo or a custom domain); Apple also needs the association file
      served as `application/json`, which Pages cannot do; the release
      signing fingerprint has to join `assetlinks.json`; deferred deep
      links need AppsFlyer
