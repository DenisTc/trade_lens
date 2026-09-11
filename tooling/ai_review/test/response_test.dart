import 'package:ai_review/ai_review.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('parseMessage', () {
    test('joins the text blocks and reads the usage', () {
      const body = r'''
{"type": "message", "stop_reason": "end_turn",
 "content": [{"type": "text", "text": "{\"fin"}, {"type": "text", "text": "dings\": []}"}],
 "usage": {"input_tokens": 1200, "output_tokens": 34}}''';

      final message = parseMessage(body).valueOrNull!;

      expect(message.text, '{"findings": []}');
      expect(message.usage.inputTokens, 1200);
      expect(message.usage.outputTokens, 34);
      expect(message.stopReason, 'end_turn');
    });

    test('an API error is an error, not empty text', () {
      const body =
          '{"type": "error", "error": {"type": "overloaded_error", '
          '"message": "Overloaded"}}';

      expect(parseMessage(body), isA<Err<Object, String>>());
      expect('${parseMessage(body)}', contains('Overloaded'));
    });

    test('missing usage counts as nothing spent, not a crash', () {
      const body = '{"content": [{"type": "text", "text": "x"}]}';

      expect(parseMessage(body).valueOrNull!.usage.total, 0);
    });

    test('a body that is not JSON is reported', () {
      expect(parseMessage('<html>502</html>'), isA<Err<Object, String>>());
    });
  });
}
