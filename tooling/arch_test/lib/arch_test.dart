/// Helpers for the architecture tests: read the workspace layout and scan
/// Dart sources. Rules themselves live in `test/`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Walks up from the current directory until it finds the workspace root
/// (the `pubspec.yaml` that declares `workspace:`).
Directory findWorkspaceRoot([Directory? from]) {
  var dir = (from ?? Directory.current).absolute;
  while (true) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      final doc = loadYaml(pubspec.readAsStringSync());
      if (doc is YamlMap && doc.containsKey('workspace')) return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('workspace root not found above ${Directory.current}');
    }
    dir = parent;
  }
}

/// One workspace package: its name and directory.
class WorkspacePackage {
  const WorkspacePackage({required this.name, required this.dir});

  final String name;
  final Directory dir;

  Directory get lib => Directory(p.join(dir.path, 'lib'));

  /// Names of `dependencies` and `dev_dependencies` from `pubspec.yaml`.
  Set<String> get dependencies {
    final doc = loadYaml(
      File(p.join(dir.path, 'pubspec.yaml')).readAsStringSync(),
    );
    final result = <String>{};
    for (final section in ['dependencies', 'dev_dependencies']) {
      final deps = (doc as YamlMap)[section];
      if (deps is YamlMap) result.addAll(deps.keys.cast<String>());
    }
    return result;
  }

  /// Relative path used as the key in the allow-list, e.g. `features/markets`.
  String relativeTo(Directory root) => p.relative(dir.path, from: root.path);
}

/// All packages listed under `workspace:` in the root pubspec.
List<WorkspacePackage> workspacePackages(Directory root) {
  final doc = loadYaml(
    File(p.join(root.path, 'pubspec.yaml')).readAsStringSync(),
  );
  final entries = (doc as YamlMap)['workspace'] as YamlList;
  return [
    for (final entry in entries.cast<String>())
      WorkspacePackage(
        name: _packageName(Directory(p.join(root.path, entry))),
        dir: Directory(p.join(root.path, entry)),
      ),
  ];
}

String _packageName(Directory dir) {
  final doc = loadYaml(
    File(p.join(dir.path, 'pubspec.yaml')).readAsStringSync(),
  );
  return (doc as YamlMap)['name'] as String;
}

/// Dependencies of [pkg] that are other workspace packages.
Set<String> internalDependencies(
  WorkspacePackage pkg,
  List<WorkspacePackage> all,
) {
  final internal = {for (final other in all) other.name};
  return pkg.dependencies.intersection(internal);
}

/// Hand-written Dart sources under `lib/`. Generated files are skipped:
/// they inherit whatever the source file imports.
Iterable<File> dartSources(Directory lib) {
  if (!lib.existsSync()) return const [];
  return lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !_isGenerated(f.path));
}

bool _isGenerated(String path) =>
    path.endsWith('.g.dart') ||
    path.endsWith('.freezed.dart') ||
    path.endsWith('.drift.dart');

/// Package names imported by [file] via `package:` URIs.
Set<String> importedPackages(File file) {
  final pattern = RegExp(
    r'''^\s*(?:import|export)\s+['"]package:([a-z0-9_]+)/''',
    multiLine: true,
  );
  return {
    for (final m in pattern.allMatches(file.readAsStringSync())) m.group(1)!,
  };
}
