import 'dart:typed_data';

import 'package:data_market/data_market.dart';
import 'package:test/test.dart';

Uint8List _hex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

void main() {
  group('extractSpki rejects hand-crafted DER', () {
    test('empty outer sequences are not walked past their own end', () {
      // 30 00 = empty certificate SEQUENCE, followed by loose elements that
      // a parser without parent bounds would happily read as tbs fields.
      expect(
        () => extractSpki(_hex('30003000020030003000300030003000')),
        throwsFormatException,
      );
    });

    test('an SPKI without the algorithm/key shape is rejected', () {
      // cert { tbs { serial, sig, issuer, validity, subject, spki=SEQUENCE{} } }
      const tbs =
          '020100' // serial
          '3000' // signature
          '3000' // issuer
          '3000' // validity
          '3000' // subject
          '3000'; // spki: empty, no algorithm / key
      final cert =
          '30${(tbs.length ~/ 2 + 2).toRadixString(16).padLeft(2, '0')}30${(tbs.length ~/ 2).toRadixString(16).padLeft(2, '0')}$tbs';
      expect(() => extractSpki(_hex(cert)), throwsFormatException);
    });

    test('a truncated buffer is rejected', () {
      expect(() => extractSpki(_hex('3082')), throwsFormatException);
      expect(() => extractSpki(_hex('308201')), throwsFormatException);
    });

    test('a well-formed minimal SPKI is accepted and returned whole', () {
      // spki = SEQUENCE { SEQUENCE {}, BIT STRING 00 }
      const spki =
          '3005'
          '3000'
          '030100';
      const tbs =
          '020100' // serial
          '3000' // signature
          '3000' // issuer
          '3000' // validity
          '3000' // subject
          '$spki';
      final cert =
          '30${(tbs.length ~/ 2 + 2).toRadixString(16).padLeft(2, '0')}30${(tbs.length ~/ 2).toRadixString(16).padLeft(2, '0')}$tbs';
      expect(extractSpki(_hex(cert)), _hex(spki));
    });
  });
}
