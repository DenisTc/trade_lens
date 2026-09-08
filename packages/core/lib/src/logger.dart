/// Minimal logging facade so packages do not depend on a logging library
/// or on Sentry. The app decides where lines go.
abstract interface class Logger {
  void debug(String message);
  void info(String message);
  void warn(String message, [Object? error]);
  void error(String message, [Object? error, StackTrace? stackTrace]);
}

/// Default for tests and pure-Dart tooling.
final class NoopLogger implements Logger {
  const NoopLogger();

  @override
  void debug(String message) {}
  @override
  void info(String message) {}
  @override
  void warn(String message, [Object? error]) {}
  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {}
}

/// Writes to [sink] (defaults to `print`) with a level prefix.
final class PrintLogger implements Logger {
  const PrintLogger({this.tag = 'tradelens', this.sink});

  final String tag;
  final void Function(String line)? sink;

  void _emit(String level, String message, [Object? error, StackTrace? st]) {
    final buffer = StringBuffer('[$tag] $level $message');
    if (error != null) buffer.write(' · $error');
    if (st != null) buffer.write('\n$st');
    final line = buffer.toString();
    (sink ?? print)(line);
  }

  @override
  void debug(String message) => _emit('D', message);
  @override
  void info(String message) => _emit('I', message);
  @override
  void warn(String message, [Object? error]) => _emit('W', message, error);
  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _emit('E', message, error, stackTrace);
}
