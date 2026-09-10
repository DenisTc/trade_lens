import 'dart:convert';

import 'package:ai_insights/ai_insights.dart';
import 'package:core/core.dart';

/// One non-streaming Messages response: the text the model produced and
/// what it cost.
typedef Message = ({String text, Usage usage, String? stopReason});

/// Parses `POST /v1/messages` without `stream`. The structured answer is
/// a text block, so the blocks are joined and handed to the schema parser
/// by the caller.
Result<Message, String> parseMessage(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException catch (e) {
    return Err('the response is not JSON: ${e.message}');
  }
  if (decoded is! Map<String, Object?>) return const Err('expected an object');
  if (decoded['type'] == 'error') {
    final error = decoded['error'];
    final message = error is Map<String, Object?> ? error['message'] : null;
    return Err('the API returned an error: ${message ?? decoded['error']}');
  }
  final content = decoded['content'];
  if (content is! List) return const Err('expected a content array');

  final text = StringBuffer();
  for (final block in content) {
    if (block is Map<String, Object?> &&
        block['type'] == 'text' &&
        block['text'] is String) {
      text.write(block['text']);
    }
  }

  final usage = decoded['usage'];
  return Ok((
    text: text.toString(),
    usage: usage is Map<String, Object?>
        ? Usage(
            inputTokens: _int(usage['input_tokens']),
            outputTokens: _int(usage['output_tokens']),
          )
        : const Usage(),
    stopReason: decoded['stop_reason'] is String
        ? decoded['stop_reason']! as String
        : null,
  ));
}

int _int(Object? v) => v is int && v > 0 ? v : 0;
