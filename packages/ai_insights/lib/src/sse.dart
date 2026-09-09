import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

/// One Server-Sent Event: `event:` name and the joined `data:` lines.
@immutable
final class SseEvent {
  const SseEvent({required this.event, required this.data});

  final String event;
  final String data;

  @override
  bool operator ==(Object other) =>
      other is SseEvent && other.event == event && other.data == data;

  @override
  int get hashCode => Object.hash(event, data);

  @override
  String toString() => 'SseEvent($event, $data)';
}

/// Turns a byte stream into SSE events. Chunks may split lines, events and
/// even UTF-8 sequences anywhere; the parser buffers until a blank line
/// ends the event. Comment lines (`:`) and unknown fields are ignored.
final class SseDecoder extends StreamTransformerBase<List<int>, SseEvent> {
  const SseDecoder();

  @override
  Stream<SseEvent> bind(Stream<List<int>> stream) => stream
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .transform(const _EventAssembler());
}

final class _EventAssembler extends StreamTransformerBase<String, SseEvent> {
  const _EventAssembler();

  @override
  Stream<SseEvent> bind(Stream<String> lines) async* {
    var event = '';
    final data = <String>[];
    await for (final line in lines) {
      if (line.isEmpty) {
        if (data.isNotEmpty) {
          yield SseEvent(event: event, data: data.join('\n'));
        }
        event = '';
        data.clear();
        continue;
      }
      if (line.startsWith(':')) continue;
      final colon = line.indexOf(':');
      final field = colon < 0 ? line : line.substring(0, colon);
      var value = colon < 0 ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      switch (field) {
        case 'event':
          event = value;
        case 'data':
          data.add(value);
        default:
          break;
      }
    }
    if (data.isNotEmpty) yield SseEvent(event: event, data: data.join('\n'));
  }
}
