import 'dart:async';

import 'package:on_device_llm/src/messages.g.dart';

export 'src/messages.g.dart' show OnDeviceAvailability;

/// Injectable boundary for on-device generation. No cloud fallback is performed.
abstract interface class OnDeviceLlmApi {
  Future<OnDeviceAvailability> availability(String languageCode);

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
  Future<void> _generationTransition = Future.value();
  _Generation? _activeGeneration;

  @override
  Future<OnDeviceAvailability> availability(String languageCode) =>
      _hostApi.availability(languageCode);

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
    final result = Completer<String>();
    final request = OnDeviceRequest(
      system: system,
      prompt: prompt,
      languageCode: languageCode,
      maxOutputChars: maxOutputChars,
    );
    final transition = _generationTransition.then((_) async {
      final previous = _activeGeneration;
      if (previous != null) {
        try {
          await _hostApi.cancel();
        } finally {
          await previous.settled;
        }
      }

      final generation = _Generation(_hostApi.generate(request));
      _activeGeneration = generation;
      unawaited(
        generation.result.then(result.complete, onError: result.completeError),
      );
      unawaited(
        generation.settled.then((_) {
          if (identical(_activeGeneration, generation)) {
            _activeGeneration = null;
          }
        }),
      );
    });
    _generationTransition = transition.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        if (!result.isCompleted) result.completeError(error, stackTrace);
      },
    );
    return result.future;
  }

  @override
  Future<void> cancel() async {
    // A first generation is started from the transition queue. Wait until it
    // has reached the host so an immediate caller cancellation cannot miss it.
    await _generationTransition;
    await _hostApi.cancel();
  }

  @override
  Future<String> runtimeName() => _hostApi.describeRuntime();
}

final class _Generation {
  _Generation(this.result)
    : settled = result.then<void>((_) {}, onError: (_, _) {});

  final Future<String> result;
  final Future<void> settled;
}
