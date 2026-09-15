import 'dart:async';

import 'package:features_shared/features_shared.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('availability is probed in the app language and cached', () async {
    final llm = _FakeOnDeviceLlm(OnDeviceAvailability.available);
    final container = ProviderContainer(
      overrides: [
        onDeviceLlmProvider.overrideWithValue(llm),
        appLanguageCodeProvider.overrideWithValue('ru'),
      ],
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
    expect(llm.languageCodes, ['ru']);
  });

  test('refresh keeps the cached value visible while re-probing', () async {
    final refresh = Completer<OnDeviceAvailability>();
    final llm = _FakeOnDeviceLlm(OnDeviceAvailability.available);
    final container = ProviderContainer(
      overrides: [
        onDeviceLlmProvider.overrideWithValue(llm),
        appLanguageCodeProvider.overrideWithValue('vi'),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await container.read(onDeviceAvailabilityProvider.future),
      OnDeviceAvailability.available,
    );
    llm.nextAvailability = refresh.future;
    final refreshing = container
        .read(onDeviceAvailabilityProvider.notifier)
        .refresh();
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(onDeviceAvailabilityProvider).value,
      OnDeviceAvailability.available,
    );
    expect(llm.languageCodes, ['vi', 'vi']);
    refresh.complete(OnDeviceAvailability.unsupportedLanguage);
    await refreshing;
    expect(
      container.read(onDeviceAvailabilityProvider).value,
      OnDeviceAvailability.unsupportedLanguage,
    );
  });
}

final class _FakeOnDeviceLlm implements OnDeviceLlmApi {
  _FakeOnDeviceLlm(this.status);

  final OnDeviceAvailability status;
  Future<OnDeviceAvailability>? nextAvailability;
  int availabilityCalls = 0;
  final languageCodes = <String>[];

  @override
  Future<OnDeviceAvailability> availability(String languageCode) async {
    availabilityCalls++;
    languageCodes.add(languageCode);
    if (nextAvailability case final availability?) {
      nextAvailability = null;
      return await availability;
    }
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
