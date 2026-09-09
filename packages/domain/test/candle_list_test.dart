import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

Candle _c(int minute, {String close = '10'}) => Candle(
  openTime: DateTime.utc(2026, 9, 9, 12, minute),
  open: Decimal.parse('10'),
  high: Decimal.parse('11'),
  low: Decimal.parse('9'),
  close: Decimal.parse(close),
  volume: Decimal.one,
);

void main() {
  test('upsert replaces the same openTime', () {
    final list = [_c(0), _c(1)].upsert(_c(1, close: '12'));
    expect(list, hasLength(2));
    expect(list.last.close, Decimal.parse('12'));
  });

  test('upsert appends newer and inserts older in order', () {
    final list = [_c(0), _c(3)].upsert(_c(4)).upsert(_c(2)).upsert(_c(1));
    expect(list.map((c) => c.openTime.minute), [0, 1, 2, 3, 4]);
  });

  test('upsert on an empty list', () {
    expect(<Candle>[].upsert(_c(0)), hasLength(1));
  });

  test('granularity is the median spacing', () {
    expect([_c(0), _c(30), _c(60)].granularity, const Duration(minutes: 30));
    expect([_c(0)].granularity, isNull);
  });
}
