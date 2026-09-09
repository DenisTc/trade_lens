import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Golden tests render text with Roboto from the Flutter SDK instead of the
/// "Ahem" placeholder, so the images look like the app and stay identical
/// across machines that pin the same Flutter version (`.fvmrc`).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadRoboto();
  await testMain();
}

Future<void> _loadRoboto() async {
  // `flutter test` runs the Dart VM from <root>/bin/cache/dart-sdk/bin.
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final dir = Directory('$flutterRoot/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  final loader = FontLoader('Roboto');
  for (final file in dir.listSync().whereType<File>()) {
    if (file.path.endsWith('.ttf') && file.path.contains('Roboto-')) {
      loader.addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
  }
  await loader.load();
}
