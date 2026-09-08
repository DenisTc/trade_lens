import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tradelens/observability/sentry_filters.dart';

/// DSN comes from `--dart-define-from-file=env.json`; an empty value (the
/// committed `env.example.json`, CI) runs the app without Sentry.
const sentryDsn = String.fromEnvironment('SENTRY_DSN');

/// Starts Sentry around [runApp] when a DSN is present, otherwise just runs.
Future<void> runWithSentry(FutureOr<void> Function() runApp) async {
  if (sentryDsn.isEmpty) {
    await runApp();
    return;
  }
  await SentryFlutter.init((options) {
    options
      ..dsn = sentryDsn
      ..environment = kReleaseMode ? 'release' : 'debug'
      ..tracesSampleRate = 0
      ..sendDefaultPii = false
      ..beforeBreadcrumb = sanitizeBreadcrumb;
  }, appRunner: runApp);
}
