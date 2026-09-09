import 'dart:io';

import 'package:arch_test/arch_test.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Money and quantities are `Decimal` (spec: "никаких double в деньгах").
/// The domain package is the place where a stray `double` would spread
/// to every layer, so it is banned there entirely.
void main() {
  final root = findWorkspaceRoot();
  final domainLib = Directory(p.join(root.path, 'packages', 'domain', 'lib'));
  final doubleToken = RegExp(r'\bdouble\b');

  test('domain sources never mention double', () {
    final offenders = <String>[];
    for (final file in dartSources(domainLib)) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('//')) continue; // comments may explain the ban
        if (doubleToken.hasMatch(line)) {
          offenders.add('${p.relative(file.path, from: root.path)}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'use Decimal instead of double');
  });
}
