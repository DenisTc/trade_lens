import 'package:core/core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'error_reporter.g.dart';

/// Where features send handled, non-fatal errors (a broken remote config,
/// a rejected AI response). The app overrides it with Sentry; tests read
/// what was reported.
abstract interface class ErrorReporter {
  void report(Object error, {StackTrace? stackTrace, String? hint});
}

/// Logs through the core [Logger].
final class LoggingErrorReporter implements ErrorReporter {
  const LoggingErrorReporter(this.logger);

  final Logger logger;

  @override
  void report(Object error, {StackTrace? stackTrace, String? hint}) =>
      logger.error(hint ?? 'handled error', error, stackTrace);
}

@Riverpod(keepAlive: true)
ErrorReporter errorReporter(Ref ref) =>
    const LoggingErrorReporter(PrintLogger());
