import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tradelens/providers/app_info.dart';
import 'package:tradelens/router.dart';
import 'package:tradelens/theme.dart';

/// Root widget: theme, router. Localization delegates arrive on day 5.
class TradeLensApp extends ConsumerWidget {
  const TradeLensApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: ref.watch(appNameProvider),
      theme: TradeLensTheme.light,
      darkTheme: TradeLensTheme.dark,
      routerConfig: router,
    );
  }
}
