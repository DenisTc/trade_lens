# AI move summary (Claude API)

Spec: `docs/spec/tradelens-prd-tid-v1.2.md`, «AI-сводка движения через Claude API».

- [x] `ai_insights`: SSE decoder (chunk- and UTF-8-boundary safe), typed stream events, tool schemas with allowlists, tool runner rendering compact CSV, session with the 3-iteration loop and token budget, structured second call, usage and cost, typed errors
- [x] `domain`: `SecretStore` + `SecretKeys`; `InsightsConfig.aiModelJson`; `data_local`: `SecureSecretStore` (Keychain / Keystore)
- [x] `data_market`: `DioClaudeTransport` (SPKI pinning, no retries, streamed body, key only on the header)
- [x] `features_shared`: key and consent providers, `aiReadiness`
- [x] `features_insights`: controller, sheet (consent gate, streaming prose, tool chips, structured block, cost, disclaimer), Riverpod tools adapter, recorded-example transport + bilingual asset
- [x] `features_settings`: key screen (masked, keychain-only) and consent switch; hub row
- [x] App: DI, `/settings/ai`, the pair-screen button behind the remote flag, `TL_AI_DEMO`
- [x] Tests: 17 in `ai_insights`, provider tests, sheet widget tests, settings tests, app test, two goldens
- [x] Codex cross-review, two passes: pin checked before the key is sent (`SpkiPreflight`), redirects refused, unsupported JSON-schema keywords dropped and enforced locally, cancellation racing a stalled stream, cumulative usage billed once, tool rounds capped exactly, budget checked before spending and `max_tokens` clamped to what is left, cost kept after a failed attempt, tools read only providers that already exist, source attribution taken from the app instead of the model, attempt guard against overlapping retries
- [x] Release
