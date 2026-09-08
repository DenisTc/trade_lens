import 'package:arch_test/arch_test.dart';
import 'package:test/test.dart';

/// Layer rules from the spec ("Архитектура и пакеты"): the app depends on
/// features, features on domain/core and infrastructure packages, data
/// implements domain interfaces. Keys are workspace-relative paths.
const allowedInternalDependencies = <String, Set<String>>{
  'packages/core': {},
  'packages/domain': {'core'},
  'packages/ws_client': {'core'},
  'packages/data_market': {'core', 'domain', 'ws_client'},
  'packages/data_local': {'core', 'domain'},
  'packages/chart': {'core'},
  'packages/sdui': {'core'},
  'packages/ai_insights': {'core', 'domain'},
  'packages/features/markets': _featureDeps,
  'packages/features/portfolio': _featureDeps,
  'packages/features/insights': _featureDeps,
  'packages/features/settings': _featureDeps,
  'tooling/arch_test': {},
  // apps/mobile is intentionally absent: it may depend on anything.
};

/// Features see interfaces (`domain`) and pure UI packages. Implementations
/// (`data_market`, `data_local`, `ws_client`, `ai_insights`) are wired in
/// `apps/mobile` through Riverpod overrides, never imported by a feature.
const _featureDeps = <String>{'core', 'domain', 'chart', 'sdui'};

void main() {
  final root = findWorkspaceRoot();
  final packages = workspacePackages(root);

  test('every workspace package has a rule or is the app', () {
    for (final pkg in packages) {
      final key = pkg.relativeTo(root);
      if (key == 'apps/mobile') continue;
      expect(
        allowedInternalDependencies,
        contains(key),
        reason: 'add $key to allowedInternalDependencies',
      );
    }
  });

  test('pubspec dependencies respect the layer rules', () {
    for (final pkg in packages) {
      final allowed = allowedInternalDependencies[pkg.relativeTo(root)];
      if (allowed == null) continue;
      final actual = internalDependencies(pkg, packages);
      expect(
        actual.difference(allowed),
        isEmpty,
        reason: '${pkg.name} depends on forbidden packages',
      );
    }
  });

  test('imports respect the layer rules even without a pubspec entry', () {
    final internalNames = {for (final p in packages) p.name};
    for (final pkg in packages) {
      final allowed = allowedInternalDependencies[pkg.relativeTo(root)];
      if (allowed == null) continue;
      for (final file in dartSources(pkg.lib)) {
        final imported = importedPackages(file).intersection(internalNames)
          ..remove(pkg.name);
        expect(
          imported.difference(allowed),
          isEmpty,
          reason: '${file.path} imports a forbidden package',
        );
      }
    }
  });

  test('features do not depend on each other', () {
    final features = packages.where((p) => p.name.startsWith('features_'));
    final featureNames = {for (final f in features) f.name};
    for (final pkg in features) {
      final crossFeature = internalDependencies(
        pkg,
        packages,
      ).intersection(featureNames)..remove(pkg.name);
      expect(
        crossFeature,
        isEmpty,
        reason: '${pkg.name} imports a sibling feature',
      );
    }
  });
}
