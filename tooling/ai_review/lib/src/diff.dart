import 'dart:convert';

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
  final starts = [
    for (var i = 0; i < lines.length; i++)
      if (lines[i].startsWith('diff --git ')) i,
  ];
  for (var i = 0; i < starts.length; i++) {
    final end = i + 1 < starts.length ? starts[i + 1] : lines.length;
    final chunk = lines.sublist(starts[i], end);
    final path = _pathOf(chunk);
    if (path != null) out.add((path: path, body: '${chunk.join('\n')}\n'));
  }
  return out;
}

/// The path of one file chunk.
///
/// The `diff --git a/x b/x` header is ambiguous — a path may itself
/// contain ` b/`, and an unusual name arrives C-quoted — so the header is
/// the last resort. `+++ b/`, `rename to` and `--- a/` (a deletion) each
/// carry the path on their own.
String? _pathOf(List<String> chunk) {
  final header = <String>[];
  for (final line in chunk) {
    if (line.startsWith('@@')) break;
    header.add(line);
  }
  for (final line in header) {
    if (line.startsWith('+++ b/')) return _unquote(line.substring(6));
    if (line.startsWith('rename to ')) return _unquote(line.substring(10));
  }
  for (final line in header) {
    if (line.startsWith('--- a/')) return _unquote(line.substring(6));
  }
  return _fromHeader(header.first);
}

/// `diff --git a/lib/x.dart b/lib/x.dart` → `lib/x.dart`, for the chunks
/// that carry nothing else: a mode change, or a rename with no content.
String? _fromHeader(String header) {
  final rest = header.substring('diff --git '.length);
  if (rest.startsWith('"')) {
    // Two quoted paths; the second one is the new name.
    final second = rest.lastIndexOf('"b/');
    if (second < 0) return null;
    return _unquote(rest.substring(second).replaceFirst('"b/', '"'));
  }
  // A path can contain " b/", so the halves are matched on length: git
  // writes `a/<p> b/<q>` and only a rename makes p and q differ.
  final i = rest.indexOf(' b/', (rest.length - 3) ~/ 2);
  if (i < 0 || !rest.startsWith('a/')) return null;
  return rest.substring(i + 3).trim();
}

/// Git C-quotes a path with unusual bytes: `"caf\303\251.dart"`.
String _unquote(String raw) {
  final path = raw.trim();
  if (!path.startsWith('"') || !path.endsWith('"') || path.length < 2) {
    return path;
  }
  final body = path.substring(1, path.length - 1);
  final bytes = <int>[];
  for (var i = 0; i < body.length; i++) {
    if (body[i] != r'\') {
      bytes.addAll(utf8.encode(body[i]));
      continue;
    }
    final next = i + 1 < body.length ? body[i + 1] : '';
    final octal = i + 3 < body.length ? body.substring(i + 1, i + 4) : '';
    final code = int.tryParse(octal, radix: 8);
    if (code != null) {
      bytes.add(code);
      i += 3;
    } else {
      bytes.addAll(
        utf8.encode(switch (next) {
          't' => '\t',
          'n' => '\n',
          _ => next,
        }),
      );
      i += 1;
    }
  }
  return utf8.decode(bytes, allowMalformed: true);
}
