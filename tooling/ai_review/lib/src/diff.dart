import 'package:meta/meta.dart';

/// The part of a pull request worth reading, and what was left out.
@immutable
final class ReviewDiff {
  const ReviewDiff({
    required this.text,
    required this.files,
    required this.skipped,
    required this.truncated,
  });

  /// The unified diff handed to the model.
  final String text;

  /// Paths included, in the order they appear.
  final List<String> files;

  /// Paths left out: generated code, lock files, binaries.
  final List<String> skipped;

  /// Paths dropped because the budget ran out, not because of what they
  /// are. The comment says so, so nobody reads a partial review as a
  /// clean bill of health.
  final List<String> truncated;

  bool get isEmpty => text.trim().isEmpty;
}

/// Files a reviewer has no business reading: written by a generator, by
/// a package manager, or not text at all.
bool isReviewable(String path) {
  const generated = [
    '.g.dart',
    '.freezed.dart',
    '.drift.dart',
    '.mocks.dart',
    'firebase_options.dart',
    'l10n/app_localizations',
  ];
  const managed = [
    'pubspec.lock',
    'Gemfile.lock',
    'Package.resolved',
    'podfile.lock',
  ];
  const binary = [
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.ico', '.icns', //
    '.ttf', '.otf', '.woff', '.woff2', '.pdf', '.zip', '.jks', '.keystore',
  ];
  final lower = path.toLowerCase();
  if (generated.any(path.contains)) return false;
  if (managed.any((m) => lower.endsWith(m.toLowerCase()))) return false;
  if (binary.any(lower.endsWith)) return false;
  return true;
}

/// Splits a unified diff per file, drops what is not worth reading and
/// stops at [maxChars], so one enormous pull request cannot spend a whole
/// budget on a single call.
///
/// Files are taken in ascending size: a hundred small files say more
/// about a change than the top of one generated monster.
ReviewDiff selectDiff(String raw, {int maxChars = 120000}) {
  final chunks = _split(raw);
  final skipped = <String>[];
  final candidates = <({String path, String body})>[];
  for (final c in chunks) {
    if (isReviewable(c.path) && !c.body.contains('\nBinary files ')) {
      candidates.add(c);
    } else {
      skipped.add(c.path);
    }
  }
  candidates.sort((a, b) => a.body.length.compareTo(b.body.length));

  final taken = <({String path, String body})>[];
  final truncated = <String>[];
  var size = 0;
  for (final c in candidates) {
    if (size + c.body.length > maxChars) {
      truncated.add(c.path);
      continue;
    }
    size += c.body.length;
    taken.add(c);
  }
  // Back to the order the diff had, which is the order a reader expects.
  final order = [for (final c in chunks) c.path];
  taken.sort((a, b) => order.indexOf(a.path).compareTo(order.indexOf(b.path)));

  return ReviewDiff(
    text: taken.map((c) => c.body).join(),
    files: [for (final c in taken) c.path],
    skipped: skipped,
    truncated: truncated,
  );
}

List<({String path, String body})> _split(String raw) {
  final out = <({String path, String body})>[];
  final lines = raw.split('\n');
  var start = -1;
  String? path;
  void flush(int end) {
    final p = path;
    if (start >= 0 && p != null) {
      out.add((path: p, body: '${lines.sublist(start, end).join('\n')}\n'));
    }
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (!line.startsWith('diff --git ')) continue;
    flush(i);
    start = i;
    path = _pathOf(line);
  }
  flush(lines.length);
  return out;
}

/// `diff --git a/lib/x.dart b/lib/x.dart` → `lib/x.dart`. A rename gives
/// two paths; the new one is what a reviewer reads.
String? _pathOf(String header) {
  final parts = header.substring('diff --git '.length).split(' b/');
  if (parts.length < 2) return null;
  return parts.last.trim();
}
