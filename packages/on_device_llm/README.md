# on_device_llm

TradeLens v3's injectable Dart API and Pigeon bridge for local text generation.
The mobile app wires this package through `SummaryProvider`: local first when
available, otherwise the existing cloud or setup-hint path.

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

The iOS implementation exposes model availability separately and creates a
fresh session for each request. The Dart adapter places the requested language
in the system instructions. The host caps returned text at `maxOutputChars`
Swift characters (grapheme clusters).
The cap can truncate sentences or structured text; stage 1 returns plain text
and does not guarantee valid JSON. It is an output cap, not a generation token
budget. Calls with a nonpositive limit are rejected before reaching the host.

Only one generation may run at a time per plugin instance. The current iOS host
rejects an invalid or concurrent request with `generation_failed`. `cancel()`
cancels the stored task; cancellation also currently surfaces as
`generation_failed` to the Dart adapter, which recognizes caller cancellation
through its own `CancelSignal`. Repeated cancellation is harmless. A new call
may start after the previous future settles. No prompts or generated text are
logged or sent to a cloud provider by this package.

`runtimeName()` describes the compiled runtime, independently of model readiness:
`Apple Foundation Models` on iOS 26+ with the framework present, otherwise `none`.

Native failures become `PlatformException`s. Availability is represented by the
typed enum; generation failures from the current iOS host use
`generation_failed`, while Android uses `unsupported`. Swift uses Pigeon's
`Error`-conforming carrier to transport the `FlutterError` code/message without
adding a global retroactive conformance to Flutter's type.

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
compatible physical device. App integration is complete; Android ML Kit
generation and eligible-device verification remain pending.
