import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_device_llm/on_device_llm.dart';
import 'package:on_device_llm/src/messages.g.dart';

void main() {
  late _FakeHostApi host;
  late OnDeviceLlmApi llm;

  setUp(() {
    host = _FakeHostApi();
    llm = OnDeviceLlm(hostApi: host);
  });

  for (final availability in OnDeviceAvailability.values) {
    test('preserves availability $availability', () async {
      host.status = availability;
      expect(await llm.availability('fr'), availability);
      expect(host.availabilityLanguageCode, 'fr');
    });
  }

  test('generate forwards the request to the host API', () async {
    expect(
      await llm.generate(
        system: 'Explain only the supplied metrics.',
        prompt: 'Return: 2%; drawdown: 1%.',
        languageCode: 'fr',
        maxOutputChars: 240,
      ),
      'Le rendement est de 2 %.',
    );
    expect(host.request?.system, 'Explain only the supplied metrics.');
    expect(host.request?.prompt, 'Return: 2%; drawdown: 1%.');
    expect(host.request?.languageCode, 'fr');
    expect(host.request?.maxOutputChars, 240);
  });

  for (final limit in [0, -1]) {
    test('rejects a nonpositive output limit of $limit before host work', () {
      expect(
        () => llm.generate(
          system: 'Summarize.',
          prompt: 'Metrics.',
          languageCode: 'en',
          maxOutputChars: limit,
        ),
        throwsArgumentError,
      );
      expect(host.request, isNull);
    });
  }

  test('preserves host generation errors for the caller', () async {
    host.failure = PlatformException(code: 'model_not_ready');
    await expectLater(
      llm.generate(
        system: 'Summarize.',
        prompt: 'Metrics.',
        languageCode: 'en',
        maxOutputChars: 100,
      ),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'model_not_ready',
        ),
      ),
    );
  });

  test('cancel reaches the pending host generation', () async {
    host.pending = Completer<String>();
    final generation = llm.generate(
      system: 'Summarize.',
      prompt: 'Metrics.',
      languageCode: 'en',
      maxOutputChars: 100,
    );
    final cancelled = expectLater(
      generation,
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'cancelled',
        ),
      ),
    );
    await llm.cancel();
    await cancelled;
  });

  test('cancel is harmless without an active request', () async {
    await expectLater(llm.cancel(), completes);
  });

  test(
    'a second generate cancels and awaits the first before reaching the host',
    () async {
      host
        ..pending = Completer<String>()
        ..cancellation = Completer<void>();
      final first = llm.generate(
        system: 'First system.',
        prompt: 'First prompt.',
        languageCode: 'en',
        maxOutputChars: 100,
      );
      final firstCancelled = expectLater(
        first,
        throwsA(isA<PlatformException>()),
      );
      await Future<void>.delayed(Duration.zero);

      final second = llm.generate(
        system: 'Second system.',
        prompt: 'Second prompt.',
        languageCode: 'ru',
        maxOutputChars: 200,
      );
      await Future<void>.delayed(Duration.zero);

      expect(host.cancelCalls, 1);
      expect(host.requests, hasLength(1));
      host.cancellation!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(host.requests, hasLength(1));

      host.pending!.completeError(PlatformException(code: 'cancelled'));
      await firstCancelled;
      await Future<void>.delayed(Duration.zero);
      expect(host.requests, hasLength(2));
      expect(host.requests.last.prompt, 'Second prompt.');
      expect(await second, 'Le rendement est de 2 %.');
    },
  );

  test('runtimeName exposes the host runtime description', () async {
    expect(await llm.runtimeName(), 'Apple Foundation Models');
  });

  test(
    'consumers can inject an implementation without platform channels',
    () async {
      final OnDeviceLlmApi fake = _FakeLlm();
      expect(
        await fake.availability('en'),
        OnDeviceAvailability.unsupportedDevice,
      );
      expect(await fake.runtimeName(), 'none');
    },
  );
}

class _FakeHostApi extends OnDeviceLlmHostApi {
  OnDeviceAvailability status = OnDeviceAvailability.available;
  OnDeviceRequest? request;
  final requests = <OnDeviceRequest>[];
  String? availabilityLanguageCode;
  PlatformException? failure;
  Completer<String>? pending;
  Completer<void>? cancellation;
  int cancelCalls = 0;

  @override
  Future<OnDeviceAvailability> availability(String languageCode) async {
    availabilityLanguageCode = languageCode;
    return status;
  }

  @override
  Future<String> generate(OnDeviceRequest request) {
    this.request = request;
    requests.add(request);
    if (failure case final error?) return Future.error(error);
    if (requests.length == 1 && pending != null) return pending!.future;
    return Future.value('Le rendement est de 2 %.');
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    if (cancellation case final request?) {
      await request.future;
      return;
    }
    if (pending case final generation? when !generation.isCompleted) {
      generation.completeError(PlatformException(code: 'cancelled'));
    }
  }

  @override
  Future<String> describeRuntime() async => 'Apple Foundation Models';
}

class _FakeLlm implements OnDeviceLlmApi {
  @override
  Future<OnDeviceAvailability> availability(String languageCode) async =>
      OnDeviceAvailability.unsupportedDevice;

  @override
  Future<String> generate({
    required String system,
    required String prompt,
    required String languageCode,
    required int maxOutputChars,
  }) async => 'Fake summary';

  @override
  Future<void> cancel() async {}

  @override
  Future<String> runtimeName() async => 'none';
}
