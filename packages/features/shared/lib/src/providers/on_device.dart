import 'package:features_shared/src/providers/locale.dart';
import 'package:on_device_llm/on_device_llm.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'on_device.g.dart';

/// Native on-device generation boundary. The mobile app supplies the real
/// Pigeon implementation; tests supply a fake without platform channels.
@Riverpod(keepAlive: true)
OnDeviceLlmApi onDeviceLlm(Ref ref) =>
    throw UnimplementedError('onDeviceLlmProvider must be overridden');

/// Retains the last native capability result and supports explicit re-probes.
@Riverpod(keepAlive: true)
class OnDeviceAvailabilityProbe extends _$OnDeviceAvailabilityProbe {
  int _refreshGeneration = 0;

  @override
  Future<OnDeviceAvailability> build() =>
      _probe(ref.watch(appLanguageCodeProvider));

  /// Re-checks capability without replacing the cached value with a spinner.
  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    final result = await AsyncValue.guard(
      () => _probe(ref.read(appLanguageCodeProvider)),
    );
    if (ref.mounted && generation == _refreshGeneration) state = result;
  }

  Future<OnDeviceAvailability> _probe(String languageCode) =>
      ref.read(onDeviceLlmProvider).availability(languageCode);
}

/// Stable public name used by features and app lifecycle hooks.
final OnDeviceAvailabilityProbeProvider onDeviceAvailabilityProvider =
    onDeviceAvailabilityProbeProvider;
