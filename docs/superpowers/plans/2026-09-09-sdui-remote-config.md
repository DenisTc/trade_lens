# Server-driven Insights screen (Remote Config + SDUI)

Spec: `docs/spec/tradelens-prd-tid-v1.2.md`, «Remote Config и SDUI».

- [x] `sdui`: model (5 node types + unknown), strict parser with JSON paths in errors, schema check, route allowlist, renderer with host-supplied ticker card and navigation; tests on fixtures, unknown type, newer schema, allowlist
- [x] `domain`: `InsightsConfig`, `InsightsConfigSource`; `features_shared`: `insightsConfigSourceProvider`, `insightsConfigProvider`, `aiInsightsEnabledProvider`, `ErrorReporter`
- [x] `data_config`: `RemoteInsightsConfigSource` over a `RemoteConfigClient` interface (defaults, fetch with timeout, realtime activate, debug interval 0), `DefaultsInsightsConfigSource`; tests with a fake client
- [x] `features_insights`: `InsightsModel` keeping the last valid screen and reporting rejects, `InsightsScreen`, live `TickerCard`, bundled default JSON; widget tests
- [x] App: Firebase init with stub detection, DI, `/insights` route and tab, Sentry reporter, `remoteconfig.template.json` published, CI stub script
- [x] Codex review (three passes, 11 findings fixed with tests), screenshots, release `v0.2.0-sdui`
