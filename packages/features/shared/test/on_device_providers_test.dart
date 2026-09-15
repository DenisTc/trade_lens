import 'package:features_shared/features_shared.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('availability is probed once and retained for all listeners', () async {
    final llm = _FakeOnDeviceLlm(OnDeviceAvailability.available);
    final container = ProviderContainer(
      overrides: [onDeviceLlmProvider.overrideWithValue(llm)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      onDeviceAvailabilityProvider,
      (_, _) {},
    );

    expect(
      await container.read(onDeviceAvailabilityProvider.future),
      OnDeviceAvailability.available,
    );
    subscription.close();
    await Future<void>.delayed(Duration.zero);
    expect(
      await container.read(onDeviceAvailabilityProvider.future),
      OnDeviceAvailability.available,
    );
    expect(llm.availabilityCalls, 1);
  });
}

final class _FakeOnDeviceLlm implements OnDeviceLlmApi {
  _FakeOnDeviceLlm(this.status);

  final OnDeviceAvailability status;
  int availabilityCalls = 0;

  @override
  Future<OnDeviceAvailability> availability() async {
    availabilityCalls++;
    return status;
  }

  @override
  Future<String> generate({
    required String system,
    required String prompt,
    required String languageCode,
    required int maxOutputChars,
  }) async => 'unused';

  @override
  Future<void> cancel() async {}

  @override
  Future<String> runtimeName() async => 'fake';
}
