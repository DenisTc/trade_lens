# on_device_llm

Stage 1 of TradeLens v3: an injectable Dart API and a Pigeon bridge for local
text generation. The mobile app does not depend on this package yet.

## Platforms

- **iOS:** Apple Foundation Models on iOS 26+, with an iOS 15 deployment target.
  Foundation Models imports and declarations are guarded. Installation uses
  `ios/on_device_llm/Package.swift` and Flutter's generated `FlutterFramework`
  package; there is no CocoaPods podspec.
- **Android:** explicit fallback, always `unsupportedDevice`; generation fails
  with `unsupported`, cancellation is a no-op, and the runtime is `none`.
  `com.google.mlkit:genai-prompt` integration is deferred until its dependency and
  behavior can be verified on Android hardware. No ML Kit dependency is declared.

## API

```dart
import 'package:on_device_llm/on_device_llm.dart';

final OnDeviceLlmApi llm = OnDeviceLlm();
if (await llm.availability() == OnDeviceAvailability.available) {
  final summary = await llm.generate(
    system: 'Explain the supplied backtest metrics without investment advice.',
    prompt: 'Return: 2%. Maximum drawdown: 1%. Trades: 6.',
    languageCode: 'en',
    maxOutputChars: 600,
  );
}
```

Inject an implementation of `OnDeviceLlmApi` in consumers. Package tests inject
a fake generated host API through `OnDeviceLlm(hostApi: ...)`.

The iOS implementation checks model availability and language support for each
request, creates a fresh session, asks for the requested language/length, and
caps the returned text at `maxOutputChars` Swift characters (grapheme clusters).
The cap can truncate sentences or structured text; stage 1 returns plain text
and does not guarantee valid JSON. It is an output cap, not a generation token
budget. Calls with a nonpositive limit are rejected before reaching the host.

Only one generation may run at a time per plugin instance. A concurrent request
fails with `busy`. `cancel()` cancels the stored task; the pending future receives
`cancelled` when the task unwinds. Repeated cancellation is harmless. A new call
may start after the previous future settles. No prompts or generated text are
logged or sent to a cloud provider by this package.

`runtimeName()` describes the compiled runtime, independently of model readiness:
`Apple Foundation Models` on iOS 26+ with the framework present, otherwise `none`.

Native failures become `PlatformException`s. iOS codes include `unsupported_os`,
`unsupported_device`, `disabled`, `model_not_ready`, `invalid_request`,
`unsupported_language`, `busy`, `cancelled`, `context_window_exceeded`,
`guardrail_violation`, `unsupported_guide`, `decoding_failure`, `rate_limited`,
`refusal`, and `generation_failed`. Swift uses Pigeon's `Error`-conforming carrier
to transport the mapped `FlutterError` code/message without adding a global
retroactive conformance to Flutter's type.

## Regenerate and verify

From this package directory:

```sh
fvm exec dart run pigeon --input pigeons/messages.dart
fvm exec flutter test
```

From the workspace root:

```sh
fvm exec sh tooling/scripts/format.sh
fvm exec melos run analyze
```

Generated Dart, Swift, and Kotlin files must be regenerated together using the
version pinned in the workspace lockfile. Runtime generation still requires a
compatible physical device. App integration and the simulator app build belong
to stage 2.
