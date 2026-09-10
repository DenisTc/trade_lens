import 'dart:convert';

import 'package:core/core.dart';
import 'package:meta/meta.dart';

/// How much a finding should hold up a merge.
enum Severity {
  /// Something that will break: a crash, a wrong result, a leak.
  blocker,

  /// A real risk the author should answer for, not necessarily now.
  risk,

  /// Worth saying once, never worth blocking on.
  nit;

  static Severity? parse(Object? v) =>
      Severity.values.where((s) => s.name == v).firstOrNull;
}

@immutable
final class Finding {
  const Finding({
    required this.severity,
    required this.file,
    required this.line,
    required this.title,
    required this.detail,
  });

  final Severity severity;
  final String file;

  /// Line in the file after the change, or null when the finding is about
  /// the change as a whole.
  final int? line;
  final String title;
  final String detail;

  @override
  bool operator ==(Object other) =>
      other is Finding &&
      other.severity == severity &&
      other.file == file &&
      other.line == line &&
      other.title == title &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(severity, file, line, title, detail);
}

/// What the model is asked to return, and what comes back.
abstract final class ReviewFindings {
  /// The schema of the structured response. Deliberately small: a review
  /// nobody reads is worse than no review.
  static const schema = <String, Object?>{
    'type': 'object',
    'properties': {
      'findings': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'severity': {
              'type': 'string',
              'enum': ['blocker', 'risk', 'nit'],
            },
            'file': {'type': 'string'},
            'line': {'type': 'integer'},
            'title': {'type': 'string'},
            'detail': {'type': 'string'},
          },
          'required': ['severity', 'file', 'title', 'detail'],
          'additionalProperties': false,
        },
      },
    },
    'required': ['findings'],
    'additionalProperties': false,
  };

  /// Parses the structured response. A malformed document, or a single
  /// entry that cannot be read, is an error rather than an empty review:
  /// dropping a blocker and printing "nothing found" is the one failure
  /// this tool must not have.
  static Result<List<Finding>, String> parse(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (e) {
      return Err('the response is not JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) {
      return const Err('expected an object');
    }
    final list = decoded['findings'];
    if (list is! List) return const Err('expected a findings array');

    final out = <Finding>[];
    for (final item in list) {
      if (item is! Map<String, Object?>) {
        return const Err('a finding is not an object');
      }
      final severity = Severity.parse(item['severity']);
      final file = item['file'];
      final title = item['title'];
      final detail = item['detail'];
      if (severity == null ||
          file is! String ||
          file.isEmpty ||
          title is! String ||
          title.isEmpty ||
          detail is! String) {
        return Err('a finding is missing what a reader needs: $item');
      }
      final line = item['line'];
      out.add(
        Finding(
          severity: severity,
          file: file,
          line: line is int && line > 0 ? line : null,
          title: title,
          detail: detail,
        ),
      );
    }
    out.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    return Ok(out);
  }
}
