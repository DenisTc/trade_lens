import 'package:features_shared/features_shared.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tradelens/app.dart';
import 'package:tradelens/di/market_di.dart';
import 'package:tradelens/di/socket_lifecycle.dart';
import 'package:tradelens/di/storage_di.dart';
import 'package:tradelens/observability/sentry_setup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await runWithSentry(
    () => runApp(
      ProviderScope(
        // Retries live in the data layer (Dio, resolver, socket); a second
        // retry loop in Riverpod would only hide errors behind a spinner.
        retry: noRetry,
        overrides: [...storageOverrides(), ...marketOverrides()],
        child: const SocketLifecycle(child: TradeLensApp()),
      ),
    ),
  );
}
