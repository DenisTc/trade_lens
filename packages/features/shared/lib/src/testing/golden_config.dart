import 'dart:async';
import 'dart:io';

import 'package:features_shared/src/theme/tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shared `flutter_test_config.dart` body for packages with goldens:
/// loads the app fonts (Onest, IBM Plex Mono) from this package plus
/// Roboto from the Flutter SDK (Ahem otherwise) and installs a
/// comparator with a small pixel tolerance, because anti-aliasing differs
/// slightly even between two macOS machines (0.05 % in CI) while a real
/// regression moves whole rows of pixels.
Future<void> configureGoldenTests(
  FutureOr<void> Function() testMain, {
  double tolerance = 0.005,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadAppFonts();
  await _loadRoboto();
  final current = goldenFileComparator;
  if (current is LocalFileComparator) {
    goldenFileComparator = TolerantGoldenComparator(
      current.basedir.resolve('placeholder_test.dart'),
      tolerance: tolerance,
    );
  }
  await testMain();
}

/// Passes when the differing pixel share is at or below [tolerance].
class TolerantGoldenComparator extends LocalFileComparator {
  TolerantGoldenComparator(super.testFile, {required this.tolerance});

  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) return true;
    await generateFailureOutput(result, golden, basedir);
    throw FlutterError(
      'Golden "$golden": ${result.error} '
      '(${(result.diffPercent * 100).toStringAsFixed(2)}% > '
      '${(tolerance * 100).toStringAsFixed(2)}% tolerance)',
    );
  }
}

/// The fonts live in `features_shared/assets/fonts`; found by walking up
/// from the test's working directory to the workspace root.
Future<void> _loadAppFonts() async {
  var dir = Directory.current;
  Directory? fonts;
  for (var i = 0; i < 6 && fonts == null; i++) {
    final candidate = Directory(
      '${dir.path}/packages/features/shared/assets/fonts',
    );
    if (candidate.existsSync()) fonts = candidate;
    dir = dir.parent;
  }
  if (fonts == null) return;
  for (final (family, prefix) in [
    (TradeLensFonts.sans, 'Onest-'),
    (TradeLensFonts.mono, 'IBMPlexMono-'),
  ]) {
    final loader = FontLoader(family);
    for (final file in fonts.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (name.startsWith(prefix) && name.endsWith('.ttf')) {
        loader.addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
      }
    }
    await loader.load();
  }
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
