import 'package:on_device_llm/src/messages.g.dart';

export 'src/messages.g.dart' show OnDeviceAvailability;

/// Injectable boundary for on-device generation. No cloud fallback is performed.
abstract interface class OnDeviceLlmApi {
  Future<OnDeviceAvailability> availability();

  /// Generates text in [languageCode], capped at [maxOutputChars] characters.
  ///
  /// The limit must be positive. Native failures surface as PlatformException.
  Future<String> generate({
    required String system,
    required String prompt,
    required String languageCode,
    required int maxOutputChars,
  });

  Future<void> cancel();

  Future<String> runtimeName();
}

/// Pigeon-backed implementation of [OnDeviceLlmApi].
class OnDeviceLlm implements OnDeviceLlmApi {
  OnDeviceLlm({OnDeviceLlmHostApi? hostApi})
    : _hostApi = hostApi ?? OnDeviceLlmHostApi();

  final OnDeviceLlmHostApi _hostApi;

  @override
  Future<OnDeviceAvailability> availability() => _hostApi.availability();

  @override
  Future<String> generate({
    required String system,
    required String prompt,
    required String languageCode,
    required int maxOutputChars,
  }) {
    if (maxOutputChars <= 0) {
      throw ArgumentError.value(
        maxOutputChars,
        'maxOutputChars',
        'Must be > 0',
      );
    }
    return _hostApi.generate(
      OnDeviceRequest(
        system: system,
        prompt: prompt,
        languageCode: languageCode,
        maxOutputChars: maxOutputChars,
      ),
    );
  }

  @override
  Future<void> cancel() => _hostApi.cancel();

  @override
  Future<String> runtimeName() => _hostApi.describeRuntime();
}
