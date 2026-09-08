import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('Result', () {
    test('Ok maps value and keeps error type', () {
      const Result<int, String> r = Ok(2);
      expect(r.map((v) => v * 2), const Ok<int, String>(4));
    });

    test('Err does not map', () {
      const Result<int, String> r = Err('boom');
      expect(r.map((v) => v * 2), const Err<int, String>('boom'));
    });

    test('when dispatches on variant', () {
      const Result<int, String> ok = Ok(1);
      const Result<int, String> err = Err('e');
      expect(ok.when(ok: (v) => 'ok $v', err: (e) => 'err $e'), 'ok 1');
      expect(err.when(ok: (v) => 'ok $v', err: (e) => 'err $e'), 'err e');
    });

    test('isOk / isErr / valueOrNull', () {
      const Result<int, String> ok = Ok(1);
      const Result<int, String> err = Err('e');
      expect(ok.isOk, isTrue);
      expect(ok.isErr, isFalse);
      expect(err.isErr, isTrue);
      expect(ok.valueOrNull, 1);
      expect(err.valueOrNull, isNull);
      expect(err.errorOrNull, 'e');
    });

    test('flatMap chains', () {
      const Result<int, String> r = Ok(2);
      Result<int, String> half(int v) =>
          v.isEven ? Ok(v ~/ 2) : const Err('odd');
      expect(r.flatMap(half), const Ok<int, String>(1));
      expect(r.flatMap(half).flatMap(half), const Err<int, String>('odd'));
    });

    test('re-exports Decimal', () {
      expect(Decimal.parse('0.1') + Decimal.parse('0.2'), Decimal.parse('0.3'));
    });
  });
}
