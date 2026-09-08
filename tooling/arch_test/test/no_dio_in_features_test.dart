import 'package:arch_test/arch_test.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// HTTP lives behind `MarketDataSource` in `data_market`. Feature packages
/// and the app render `AsyncValue`; they never talk to Dio directly.
void main() {
  final root = findWorkspaceRoot();
  final packages = workspacePackages(root);
  const banned = {'dio', 'http', 'web_socket_channel'};

  test('features and app do not import HTTP clients', () {
    final targets = packages.where(
      (pkg) =>
          pkg.name.startsWith('features_') ||
          pkg.relativeTo(root) == 'apps/mobile',
    );
    final offenders = <String>[];
    for (final pkg in targets) {
      for (final file in dartSources(pkg.lib)) {
        final hit = importedPackages(file).intersection(banned);
        if (hit.isNotEmpty) {
          offenders.add('${p.relative(file.path, from: root.path)} → $hit');
        }
      }
      final inPubspec = pkg.dependencies.intersection(banned);
      if (inPubspec.isNotEmpty) {
        offenders.add('${pkg.name}/pubspec.yaml → $inPubspec');
      }
    }
    expect(offenders, isEmpty, reason: 'route HTTP through data_market');
  });
}
