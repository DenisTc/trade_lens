import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdui/sdui.dart';

void main() {
  final fixture = File('test/fixtures/insights_v1.json').readAsStringSync();

  test('parses the five node types, nests lists, keeps unknown types', () {
    final screen = SduiParser.parse(fixture).valueOrNull!;
    expect(screen.schema, 1);
    expect(screen.children, hasLength(5));
    expect(screen.children[0], isA<SduiHeader>());
    expect(
      (screen.children[0] as SduiHeader).text.resolve('ru'),
      'Рынок сегодня',
    );
    expect((screen.children[1] as SduiTickerCard).symbol, 'BTCUSDT');
    expect((screen.children[2] as SduiText).style, SduiTextStyle.muted);
    expect(
      (screen.children[3] as SduiButton).action,
      const SduiAction(route: '/p/BTCUSDT'),
    );
    final list = screen.children[4] as SduiList;
    expect((list.children[0] as SduiTickerCard).showSparkline, isFalse);
    expect((list.children[1] as SduiUnknown).type, 'surprise');
  });

  test('localized text falls back to en, then to any value', () {
    const t = LocalizedText({'en': 'Hello', 'ru': 'Привет'});
    expect(t.resolve('ru'), 'Привет');
    expect(t.resolve('de'), 'Hello');
    expect(const LocalizedText({'fr': 'Salut'}).resolve('en'), 'Salut');
    expect(const LocalizedText({}).resolve('en'), '');
  });

  test('a plain string is accepted as English text', () {
    final screen = SduiParser.parse(
      '{"schema":1,"children":[{"type":"header","text":"Hi"}]}',
    ).valueOrNull!;
    expect((screen.children.single as SduiHeader).text.resolve('ru'), 'Hi');
  });

  test('invalid JSON and a non-object root are errors', () {
    expect(SduiParser.parse('{'), isA<Err<SduiScreen, SduiParseError>>());
    expect(SduiParser.parse('[]').errorOrNull?.message, contains('object'));
  });

  test('missing required fields name their path', () {
    expect(
      SduiParser.parse('{"children":[]}').errorOrNull,
      const SduiParseError('missing int', path: r'$.schema'),
    );
    expect(SduiParser.parse('{"schema":1}').errorOrNull?.path, r'$.children');
    expect(
      SduiParser.parse('{"schema":1,"children":[{"type":"ticker_card"}]}')
          .errorOrNull
          ?.path,
      r'$.children[0].symbol',
    );
    expect(
      SduiParser.parse(
        '{"schema":1,"children":[{"type":"list","children":[{"type":"button","label":"x"}]}]}',
      ).errorOrNull?.path,
      r'$.children[0].children[0].action.route',
    );
    expect(
      SduiParser.parse(
        '{"schema":1,"children":[{"type":"text","text":{"en":1}}]}',
      ).errorOrNull?.path,
      r'$.children[0].text.en',
    );
  });

  test('a newer schema is refused, an older one renders', () {
    final newer = SduiParser.parse(
      '{"schema":${sduiSupportedSchema + 1},"children":[]}',
    );
    expect(newer.errorOrNull?.path, r'$.schema');
    expect(
      SduiParser.parse('{"schema":0,"children":[]}').valueOrNull?.schema,
      0,
    );
  });

  test('route allowlist accepts patterns and refuses everything else', () {
    final allow = SduiRouteAllowlist(['/', '/portfolio', '/p/:symbol']);
    expect(allow.allows('/'), isTrue);
    expect(allow.allows('/portfolio'), isTrue);
    expect(allow.allows('/p/BTCUSDT'), isTrue);
    expect(allow.allows('/p/BTCUSDT?from=sdui'), isTrue);
    expect(allow.allows('/p/'), isFalse);
    expect(allow.allows('/p/BTC/extra'), isFalse);
    expect(allow.allows('/settings'), isFalse);
    expect(allow.allows('https://evil.example/p/BTCUSDT'), isFalse);
    expect(allow.allows('//evil.example'), isFalse);
    expect(allow.allows('portfolio'), isFalse);
  });

  test('mistyped optional fields are errors, not crashes', () {
    expect(
      SduiParser.parse(
        '{"schema":1,"children":[{"type":"ticker_card","symbol":"X","showSparkline":"false"}]}',
      ).errorOrNull?.path,
      r'$.children[0].showSparkline',
    );
    expect(
      SduiParser.parse(
        '{"schema":1,"children":[{"type":"text","text":"x","style":"huge"}]}',
      ).errorOrNull?.path,
      r'$.children[0].style',
    );
  });

  test('budgets: input length, depth, node count, text length', () {
    expect(
      SduiParser.parse(' ' * (SduiParser.maxInputLength + 1))
          .errorOrNull
          ?.message,
      contains('longer'),
    );
    var deep = '{"type":"text","text":"x"}';
    for (var i = 0; i < SduiParser.maxDepth + 1; i++) {
      deep = '{"type":"list","children":[$deep]}';
    }
    expect(
      SduiParser.parse('{"schema":1,"children":[$deep]}').errorOrNull?.message,
      contains('deeper'),
    );
    final many = List.filled(
      SduiParser.maxNodes + 1,
      '{"type":"text","text":"x"}',
    );
    expect(
      SduiParser.parse('{"schema":1,"children":[${many.join(',')}]}')
          .errorOrNull
          ?.message,
      contains('more than'),
    );
    final long = 'x' * (SduiParser.maxTextLength + 1);
    expect(
      SduiParser.parse(
        '{"schema":1,"children":[{"type":"header","text":{"en":"$long"}}]}',
      ).errorOrNull?.message,
      contains('too long'),
    );
    expect(
      isUnsupportedSchema(
        const SduiParseError(
          'schema 9 is newer than supported 1',
          path: r'$.schema',
        ),
      ),
      isTrue,
    );
    expect(
      isUnsupportedSchema(
        const SduiParseError('missing int', path: r'$.schema'),
      ),
      isFalse,
    );
  });
}
