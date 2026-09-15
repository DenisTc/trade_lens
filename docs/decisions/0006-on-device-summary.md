# ADR-0006 · On-device backtest summaries behind SummaryProvider

Date: 15.09.2026  
Status: accepted; native generation not yet verified on an eligible device

## Context

The backtest engine already calculates the figures needed for an explanation.
Sending those figures to a cloud model is unnecessary when the phone has a
capable system model, and it excludes users who do not have an Anthropic key.
The local runtime must not receive candles, call tools, or infer figures that
the backtest did not produce.

Apple Foundation Models and the planned ML Kit GenAI adapter are native, OS-
and hardware-gated APIs. Their capability checks, cancellation semantics, and
supported-device rules do not fit a generic text-generation package
particularly well. A public Flutter package would also add another release
schedule between TradeLens and platform APIs that are still changing.

## Decision

Keep the thin, owned `packages/on_device_llm` Pigeon plugin instead of adopting
a pub package. Pigeon generates the typed Dart/Swift/Kotlin channel contract;
the native sides remain small enough to expose only capability, generation,
cancellation, and runtime description. `OnDeviceLlmApi` keeps platform
channels injectable in Dart tests. The current iOS host implements Foundation
Models. The current Android host implements the honest negative branch only:
it returns `unsupportedDevice`; ML Kit generation remains deferred.

`SummaryProvider` remains the feature boundary. `OnDeviceSummaryProvider`
passes the same system prompt and computed-metrics user message as the Claude
implementation, requests at most 2,000 output characters, and emits the
completed native answer as one `SummaryText` event. It reports zero cloud
tokens and zero cost. No tools are exposed to the local model.

Selection for a real backtest explanation is deterministic:

1. If native availability is `available`, run locally without an API key or
   cloud consent. Nothing leaves the device.
2. Otherwise use the existing cloud path only when its remote flag, user key,
   and consent gates are ready.
3. Otherwise keep the existing key/consent/disabled hint and recorded example.

The availability probe is a keep-alive Riverpod provider and runs once for the
app lifetime. `TL_AI_DEMO` changes only the cloud transport; it never changes
native availability and never substitutes a fake local answer. Cancelling the
sheet forwards to the native runtime, and unexpected native failures use the
existing retryable network/runtime error presentation.

## Hardware verification boundary

An iPhone 15 with the A16 Bionic can verify the negative branch: the plugin
reports `unsupportedDevice`, after which TradeLens chooses Claude when the
cloud gates are ready or shows the existing no-key hint. That phone cannot
verify local generation.

Generation with Apple Foundation Models requires an iPhone 15 Pro/Pro Max with
the A17 Pro or a newer eligible device, iOS 26, and Apple Intelligence enabled
with its model ready. Android generation will require the still-pending ML Kit
GenAI/Gemini Nano adapter and a compatible device (the intended supported set
includes Pixel 8+ but remains dependent on the installed OS and model state).
Native generation is not yet verified on an eligible device; passing Dart,
simulator, or A16 or Android fallback tests does not change that status.

## Consequences

- Backtest explanations can work offline and without a paid cloud key on an
  eligible phone.
- The UI identifies local answers and does not imply token spend.
- TradeLens owns two small native integrations and must keep their availability
  mappings current as Apple and Google revise their platform APIs.
- Release verification needs at least one A17 Pro+ iPhone. Android first needs
  its ML Kit adapter and then a compatible physical device; an iPhone 15/A16
  and the current Android host cover fallback only.
