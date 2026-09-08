import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_info.g.dart';

/// Display name of the app. Kept alive: it never changes at runtime.
@Riverpod(keepAlive: true)
String appName(Ref ref) => 'TradeLens';
