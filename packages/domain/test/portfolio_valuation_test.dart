import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  const btc = Asset(id: 'btc', symbol: 'BTC', name: 'Bitcoin');
  const eth = Asset(id: 'eth', symbol: 'ETH', name: 'Ethereum');
  final at = DateTime.utc(2026, 9, 9, 12, 40);

  Position pos(
    Asset asset,
    String qty,
    String price, {
    String quote = 'USDT',
  }) => Position(
    id: '${asset.id}-$quote',
    asset: asset,
    quote: quote,
    qty: Decimal.parse(qty),
    avgPrice: Decimal.parse(price),
    createdAt: at,
  );

  Quote quote(Asset asset, String price, {String quote = 'USDT'}) => Quote(
    instrument: Instrument(
      sourceId: 'binance',
      symbol: '${asset.symbol}$quote',
      base: asset,
      quote: quote,
    ),
    price: Decimal.parse(price),
    change24hPct: null,
    at: at,
  );

  test('values positions and sums PnL on Decimal', () {
    final v = PortfolioValuation.compute(
      positions: [pos(btc, '0.5', '60000'), pos(eth, '2', '3000')],
      quotes: {
        priceKeyOfQuote(quote(btc, '78000.10')): quote(btc, '78000.10'),
        priceKeyOfQuote(quote(eth, '2500')): quote(eth, '2500'),
      },
      asOf: at,
      isLive: true,
    );
    expect(v.entries[0].value, Decimal.parse('39000.05'));
    expect(v.entries[0].pnl, Decimal.parse('9000.05'));
    expect(v.entries[0].pnlPct!.toStringAsFixed(2), '30.00');
    expect(v.entries[1].pnl, Decimal.parse('-1000'));
    expect(v.total, Decimal.parse('44000.05'));
    expect(v.totalPnl, Decimal.parse('8000.05'));
    expect(v.totalPnlPct!.toStringAsFixed(2), '22.22');
    expect(v.unavailableCount, 0);
  });

  test('a position without a comparable quote is unavailable, not guessed', () {
    final v = PortfolioValuation.compute(
      positions: [pos(btc, '1', '60000'), pos(eth, '1', '3000')],
      quotes: {priceKeyOfQuote(quote(btc, '70000')): quote(btc, '70000')},
      asOf: at,
      isLive: true,
    );
    expect(v.entries[1].isAvailable, isFalse);
    expect(v.unavailableCount, 1);
    expect(v.total, Decimal.parse('70000'), reason: 'sum of what is known');
  });

  test('a quote in another currency does not value the position', () {
    final v = PortfolioValuation.compute(
      positions: [pos(btc, '1', '60000')],
      quotes: {
        priceKeyOfQuote(quote(btc, '70000', quote: 'USD')): quote(
          btc,
          '70000',
          quote: 'USD',
        ),
      },
      asOf: at,
      isLive: false,
    );
    expect(v.entries.single.isAvailable, isFalse);
    expect(v.total, isNull);
    expect(v.totalPnl, isNull);
  });

  test('empty portfolio has no totals', () {
    final v = PortfolioValuation.compute(
      positions: const [],
      quotes: const {},
      asOf: at,
      isLive: true,
    );
    expect(v.entries, isEmpty);
    expect(v.total, isNull);
  });

  test('zero cost gives no percentage', () {
    final v = PortfolioValuation.compute(
      positions: [pos(btc, '1', '0')],
      quotes: {priceKeyOfQuote(quote(btc, '1')): quote(btc, '1')},
      asOf: at,
      isLive: true,
    );
    expect(v.entries.single.pnlPct, isNull);
    expect(v.totalPnlPct, isNull);
  });

  test('Position.cost is qty × avgPrice', () {
    expect(pos(btc, '0.5', '60000').cost, Decimal.parse('30000'));
  });
}
