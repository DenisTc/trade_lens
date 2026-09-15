import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    swiftOut: 'ios/on_device_llm/Sources/on_device_llm/Messages.g.swift',
    kotlinOut:
        'android/src/main/kotlin/com/tradelens/on_device_llm/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.tradelens.on_device_llm'),
    dartPackageName: 'on_device_llm',
  ),
)
enum OnDeviceAvailability {
  available,
  unsupportedDevice,
  unsupportedOs,
  modelNotReady,
  disabled,
  unsupportedLanguage,
}

class OnDeviceRequest {
  OnDeviceRequest({
    required this.system,
    required this.prompt,
    required this.languageCode,
    required this.maxOutputChars,
  });

  String system;
  String prompt;
  String languageCode;
  int maxOutputChars;
}

@HostApi()
abstract class OnDeviceLlmHostApi {
  OnDeviceAvailability availability(String languageCode);

  @async
  String generate(OnDeviceRequest request);

  void cancel();

  String describeRuntime();
}
