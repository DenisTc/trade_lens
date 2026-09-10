import 'package:core/core.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tradelens/app.dart';
import 'package:tradelens/di/ai_di.dart';
import 'package:tradelens/di/config_di.dart';
import 'package:tradelens/di/deep_link_lifecycle.dart';
import 'package:tradelens/di/market_di.dart';
import 'package:tradelens/di/socket_lifecycle.dart';
import 'package:tradelens/di/storage_di.dart';
import 'package:tradelens/observability/sentry_setup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebase = await initFirebase();
  await runWithSentry(
    () => runApp(
      ProviderScope(
        // Retries live in the data layer (Dio, resolver, socket); a second
        // retry loop in Riverpod would only hide errors behind a spinner.
        retry: noRetry,
        overrides: [
          ...storageOverrides(),
          ...marketOverrides(),
          ...configOverrides(firebase: firebase),
          ...aiOverrides(),
        ],
        child: const DeepLinkLifecycle(
          // Links are worth tracing while developing, not in a release.
          logger: kDebugMode ? PrintLogger() : NoopLogger(),
          child: SocketLifecycle(child: TradeLensApp()),
        ),
      ),
    ),
  );
}
