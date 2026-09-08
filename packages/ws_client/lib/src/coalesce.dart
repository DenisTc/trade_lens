import 'dart:async';

/// Collects events that arrive within [window] of the first one and emits
/// them as a single list: the UI repaints once per frame instead of once
/// per tick. Measured before optimising: JSON parsing in an isolate was not
/// needed at these volumes, coalescing repaints was.
Stream<List<T>> coalesce<T>(Stream<T> source, Duration window) {
  late StreamController<List<T>> controller;
  StreamSubscription<T>? subscription;
  Timer? timer;
  var buffer = <T>[];

  void flush() {
    timer = null;
    if (buffer.isEmpty) return;
    final batch = buffer;
    buffer = <T>[];
    controller.add(batch);
  }

  controller = StreamController<List<T>>(
    onListen: () {
      subscription = source.listen(
        (event) {
          buffer.add(event);
          timer ??= Timer(window, flush);
        },
        onError: controller.addError,
        onDone: () {
          timer?.cancel();
          flush();
          unawaited(controller.close());
        },
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () {
      timer?.cancel();
      timer = null;
      // Not returned on purpose: a cancel future created in another zone
      // would delay our own done event (visible under a fake clock).
      unawaited(subscription?.cancel());
    },
  );
  return controller.stream;
}
