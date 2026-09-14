import 'package:core/core.dart';
import 'package:data_market/data_market.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

OrderBookLevel _l(String price, String qty) =>
    OrderBookLevel(price: Decimal.parse(price), qty: Decimal.parse(qty));

void main() {
  final btc = Instrument(
    sourceId: 'bybit',
    symbol: 'BTCUSDT',
    base: defaultAssets.first,
    quote: 'USDT',
  );
  final at = DateTime.utc(2026, 9, 11);

  test('nothing before a snapshot', () {
    final book = BybitOrderBook();

    expect(book.isValid, isFalse);
    expect(book.snapshot(btc, at: at), isNull);
    expect(book.applyDelta([_l('1', '1')], [], updateId: 1), isFalse);
  });

  test('a delta changes, adds and removes levels; sides stay sorted', () {
    final book = BybitOrderBook(depth: 3)
      ..applySnapshot(
        [_l('100', '1'), _l('99', '2'), _l('98', '3'), _l('97', '4')],
        [_l('101', '1'), _l('102', '2')],
        updateId: 10,
      );

    expect(
      book.applyDelta(
        [_l('99', '0'), _l('100.5', '5')], // 99 gone, a new best bid
        [_l('101', '9')], // resized
        updateId: 11,
      ),
      isTrue,
    );

    final snap = book.snapshot(btc, at: at)!;
    expect(snap.bids.map((l) => '${l.price}'), ['100.5', '100', '98']);
    expect(snap.bids.first.qty, Decimal.parse('5'));
    expect(snap.asks.first.qty, Decimal.parse('9'));
    expect(snap.at, at);
  });

  test(
    'a sequence that does not climb invalidates the book until a snapshot',
    () {
      final book = BybitOrderBook()
        ..applySnapshot([_l('1', '1')], [_l('2', '1')], updateId: 5);

      expect(book.applyDelta([], [], updateId: 5), isFalse);
      expect(book.isValid, isFalse);
      expect(book.snapshot(btc, at: at), isNull);
      // Later deltas stay refused: a lost frame cannot be caught up on.
      expect(book.applyDelta([], [], updateId: 7), isFalse);

      book.applySnapshot([_l('1', '1')], [_l('2', '1')], updateId: 8);
      expect(book.applyDelta([], [], updateId: 9), isTrue);
    },
  );

  test('invalidate: a frame that could not be read hides the book', () {
    final book = BybitOrderBook()
      ..applySnapshot([_l('1', '1')], [_l('2', '1')], updateId: 5)
      ..invalidate();

    expect(book.snapshot(btc, at: at), isNull);
    expect(book.applyDelta([], [], updateId: 6), isFalse);
  });
}
