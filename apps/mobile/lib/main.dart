import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tradelens/app.dart';
import 'package:tradelens/observability/sentry_setup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await runWithSentry(() => runApp(const ProviderScope(child: TradeLensApp())));
}
