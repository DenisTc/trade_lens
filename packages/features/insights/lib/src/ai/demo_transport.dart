import 'dart:async';
import 'dart:convert';

import 'package:ai_insights/ai_insights.dart';
import 'package:flutter/services.dart';

/// Bundled example answer: the prose and the structured block of one real
/// summary, recorded once. Lets the feature be demonstrated (and
/// screenshotted) without an API key and without spending anyone's tokens.
const demoSummaryAsset =
    'packages/features_insights/assets/ai/demo_summary.json';

/// Replays [demoSummaryAsset] as the API would stream it: the same SSE
/// events, so the whole client path (decoder, tool loop, structured call)
/// is exercised, only without a network. Never sends the key anywhere.
final class DemoClaudeTransport implements ClaudeTransport {
  DemoClaudeTransport({
    Future<String> Function()? load,
    this.delay = const Duration(milliseconds: 40),
  }) : _load =
           load ??
           // Not cached: a cached future belongs to the zone of the first
           // caller and never completes for a later widget test.
           (() => rootBundle.loadString(demoSummaryAsset, cache: false));

  final Future<String> Function() _load;

  /// Pause between deltas so the UI streams like the real thing.
  final Duration delay;

  int _calls = 0;

  @override
  Future<ClaudeResponse> post(
    Map<String, Object?> body, {
    required String apiKey,
    required CancelSignal cancel,
  }) async {
    final decoded = jsonDecode(await _load());
    if (decoded is! Map<String, Object?>) {
      throw const AiError.invalidResponse('malformed demo asset');
    }
    final structured = body.containsKey('output_config');
    final prose = decoded['prose'];
    final text = structured
        ? jsonEncode(decoded['structure'])
        : prose is Map<String, Object?>
        ? prose[_languageOf(body)] as String? ?? prose['en'] as String? ?? ''
        : '';
    _calls++;
    return ClaudeResponse(status: 200, body: _stream(text, cancel: cancel));
  }

  /// How many requests were replayed; the sheet shows the example badge
  /// regardless, this is for tests.
  int get calls => _calls;

  /// The language the caller asked for, read back from the system prompt
  /// the session builds (`language with code "ru"`); English otherwise.
  static String _languageOf(Map<String, Object?> body) {
    final system = body['system'];
    if (system is! String) return 'en';
    return RegExp('code "([a-z]{2})"').firstMatch(system)?.group(1) ?? 'en';
  }

  Stream<List<int>> _stream(
    String text, {
    required CancelSignal cancel,
  }) async* {
    List<int> event(Map<String, Object?> e) =>
        utf8.encode('event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n');

    yield event({
      'type': 'message_start',
      'message': {
        'usage': {'input_tokens': 0, 'output_tokens': 0},
      },
    });
    yield event({
      'type': 'content_block_start',
      'index': 0,
      'content_block': {'type': 'text', 'text': ''},
    });
    for (final word in text.split(' ')) {
      if (cancel.isCancelled) return;
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      yield event({
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'text_delta', 'text': '$word '},
      });
    }
    yield event({'type': 'content_block_stop', 'index': 0});
    yield event({
      'type': 'message_delta',
      'delta': {'stop_reason': 'end_turn'},
      'usage': {'output_tokens': 0},
    });
    yield event({'type': 'message_stop'});
  }
}
