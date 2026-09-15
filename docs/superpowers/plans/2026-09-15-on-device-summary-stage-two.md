# On-device Summary Stage Two Implementation Plan

> **For agentic workers:** Execute inline in the current workspace. The user explicitly forbids all git commands. Follow red-green-refactor and use only the requested `fvm exec` commands.

**Goal:** Select an on-device runtime for backtest explanations when available, fall back to the existing consented Claude flow, expose the runtime status in settings, and document the honest hardware verification boundary.

**Architecture:** `features_shared` owns the injectable on-device runtime and its keep-alive availability probe. `features_insights` adapts that runtime to `SummaryProvider`; the backtest controller chooses local before applying cloud readiness gates. Settings consumes only the shared provider, while the mobile composition root supplies the Pigeon-backed implementation.

**Tech Stack:** Dart 3.13, Flutter 3.47, Riverpod code generation, Pigeon plugin, Flutter gen-l10n.

**Spec:** `docs/spec/tradelens-prd-tid-v1.2.md:70`

## Global Constraints

- Run no git commands.
- Use `fvm exec dart` / `fvm exec flutter` for Dart and Flutter commands.
- Generate l10n with `fvm exec melos exec --scope=features_shared -- flutter gen-l10n`.
- Generate each changed Riverpod package with `fvm exec dart run build_runner build --delete-conflicting-outputs` from that package.
- Format with `fvm exec sh tooling/scripts/format.sh`.
- Finish with a successful `fvm exec melos run analyze`.
- The local branch receives computed metrics and performs no tool use.
- `TL_AI_DEMO` may replace the cloud transport only; it must not fake on-device availability or generation.

---

### Task 1: Shared prompt contract and on-device adapter

**Files:**
- Modify: `packages/ai_insights/lib/src/metrics_summary_session.dart`
- Create: `packages/features/insights/lib/src/ai/on_device_summary_provider.dart`
- Create: `packages/features/insights/test/on_device_summary_provider_test.dart`

**Interfaces:**
- Consumes: `OnDeviceLlmApi.generate`, `OnDeviceLlmApi.cancel`, `SummaryProvider`.
- Produces: `metricsSummaryUserPrompt(Map<String, Object?>)` and `OnDeviceSummaryProvider`.

- [ ] Add tests proving the exact runtime inputs, one whole-text event followed by zero usage and done, cancellation forwarding with `AiCancelled`, and native error mapping.
- [ ] Run the focused test and verify it fails because the adapter is absent.
- [ ] Extract the shared metrics user-message builder and implement the minimal adapter with `maxOutputChars: 2000`.
- [ ] Run the focused tests until green.

### Task 2: Shared availability providers and dependency rules

**Files:**
- Create: `packages/features/shared/lib/src/providers/on_device.dart`
- Modify: `packages/features/shared/lib/features_shared.dart`
- Modify: `packages/features/shared/lib/src/testing/test_overrides.dart`
- Modify: `packages/features/shared/pubspec.yaml`
- Modify: `packages/features/insights/pubspec.yaml`
- Modify: `tooling/arch_test/test/dependency_direction_test.dart`

**Interfaces:**
- Produces: keep-alive `onDeviceLlmProvider` and `onDeviceAvailabilityProvider`.

- [ ] Add provider tests proving availability is requested once and the instance is injectable.
- [ ] Verify the tests fail before the providers exist.
- [ ] Implement providers, safe default test override, exports, dependencies, and architecture allowlists.
- [ ] Run shared and architecture tests until green.

### Task 3: Local-first controller and sheet state

**Files:**
- Modify: `packages/features/insights/lib/src/ai/backtest_explanation_controller.dart`
- Modify: `packages/features/insights/lib/src/ai/backtest_explanation_sheet.dart`
- Modify: `packages/features/insights/lib/src/ai/summary_sheet_widgets.dart`
- Modify: `packages/features/insights/test/backtest_explanation_test.dart`

**Interfaces:**
- Produces: `BacktestExplanationState.onDevice` and local-first run selection.

- [ ] Add controller/widget tests for local-without-key, badge/state/cost behavior, and unsupported-device cloud fallback.
- [ ] Verify the new tests fail for the missing branch and badge.
- [ ] Implement availability-aware gating, cancellation safety, state propagation, badge, and hidden local cost footer.
- [ ] Run the focused Flutter test until green.

### Task 4: Settings status and localized copy

**Files:**
- Modify: `packages/features/settings/lib/src/ai_key_screen.dart`
- Modify: `packages/features/settings/test/ai_key_screen_test.dart`
- Modify: `packages/features/shared/lib/l10n/app_{en,ru,vi}.arb`

**Interfaces:**
- Consumes: `onDeviceAvailabilityProvider` only through `features_shared`.

- [ ] Add table-driven widget tests for every availability subtitle.
- [ ] Verify they fail because the row/copy is absent.
- [ ] Add the read-only row and all requested natural en/ru/vi strings, including badge and local-cost copy.
- [ ] Run gen-l10n and the focused settings tests until green.

### Task 5: Mobile composition root and generated sources

**Files:**
- Modify: `apps/mobile/pubspec.yaml`
- Modify: `apps/mobile/lib/di/ai_di.dart`
- Generate: Riverpod `*.g.dart` in changed packages.

**Interfaces:**
- Produces: app override `onDeviceLlmProvider.overrideWithValue(OnDeviceLlm())` independent of `TL_AI_DEMO`.

- [ ] Wire the plugin dependency and real host instance.
- [ ] Run build_runner separately in `features/shared` and `features/insights`.
- [ ] Run relevant app/package tests.

### Task 6: ADR, README, backlog, and final verification

**Files:**
- Create: `docs/decisions/0006-on-device-summary.md`
- Modify: `README.md`
- Modify: `docs/decisions/backlog.md`

- [ ] Document Pigeon rationale, selection order, iPhone 15/A16 fallback verification, A17 Pro generation requirement, and unverified eligible-device status.
- [ ] Add the README v3 section and skill-table row; mark the backlog implementation complete while retaining device verification work.
- [ ] Format through the repository script.
- [ ] Run `cd packages/ai_insights && fvm exec dart test`.
- [ ] Run focused and then feasible Flutter tests.
- [ ] Run `fvm exec melos run analyze` and require SUCCESS before reporting completion.
