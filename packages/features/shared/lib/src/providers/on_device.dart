import 'package:on_device_llm/on_device_llm.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'on_device.g.dart';

/// Native on-device generation boundary. The mobile app supplies the real
/// Pigeon implementation; tests supply a fake without platform channels.
@Riverpod(keepAlive: true)
OnDeviceLlmApi onDeviceLlm(Ref ref) =>
    throw UnimplementedError('onDeviceLlmProvider must be overridden');

/// Probes native capability once and retains the result for the app lifetime.
@Riverpod(keepAlive: true)
Future<OnDeviceAvailability> onDeviceAvailability(Ref ref) =>
    ref.watch(onDeviceLlmProvider).availability();
