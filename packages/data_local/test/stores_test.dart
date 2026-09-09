import 'package:core/core.dart';
import 'package:data_local/data_local.dart';
import 'package:domain/domain.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  const btc = Asset(id: 'btc', symbol: 'BTC', name: 'Bitcoin');
  const instrument = Instrument(
    sourceId: 'binance',
    symbol: 'BTCUSDT',
    base: btc,
    quote: 'USDT',
  );

  group('DriftPortfolioRepository', () {
    test('round-trips a position with Decimal precision and note', () async {
      final repo = DriftPortfolioRepository(db);
      final position = Position(
        id: 'p1',
        asset: btc,
        quote: 'USDT',
        qty: Decimal.parse('0.12345678'),
        avgPrice: Decimal.parse('60000.01'),
        createdAt: DateTime.utc(2026, 9, 9),
        note: 'cold wallet',
      );
      await repo.upsert(position);

      final stored = (await repo.positions()).single;
      expect(stored, position);
      expect(stored.qty.toString(), '0.12345678');
    });

    test('upsert updates, remove deletes, watch emits', () async {
      final repo = DriftPortfolioRepository(db);
      final base = Position(
        id: 'p1',
        asset: btc,
        quote: 'USDT',
        qty: Decimal.one,
        avgPrice: Decimal.fromInt(1),
        createdAt: DateTime.utc(2026),
      );
      final seen = <int>[];
      final sub = repo.watchPositions().listen((l) => seen.add(l.length));
      await repo.upsert(base);
      await repo.upsert(base.copyWith(qty: Decimal.fromInt(2)));
      expect((await repo.positions()).single.qty, Decimal.fromInt(2));
      await repo.remove('p1');
      expect(await repo.positions(), isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, 0);
      await sub.cancel();
    });
  });

  group('DriftLastQuoteStore', () {
    test('keeps the last price per source and instrument', () async {
      final store = DriftLastQuoteStore(db);
      Quote q(String price, DateTime at) => Quote(
        instrument: instrument,
        price: Decimal.parse(price),
        change24hPct: Decimal.parse('-1.5'),
        at: at,
      );
      await store.save(q('1', DateTime.utc(2026, 1, 1, 12)));
      await store.save(q('2', DateTime.utc(2026, 1, 1, 12, 40)));

      final all = await store.readAll('binance');
      expect(all.single.price, Decimal.fromInt(2));
      expect(all.single.at, DateTime.utc(2026, 1, 1, 12, 40));
      expect(all.single.instrument, instrument);
      expect(await store.readAll('coingecko'), isEmpty);
    });
  });

  group('DriftCandleCache', () {
    Candle candle(int i) => Candle(
      openTime: DateTime.utc(2026, 9, 9).add(Duration(minutes: i)),
      open: Decimal.fromInt(i),
      high: Decimal.fromInt(i + 1),
      low: Decimal.fromInt(i - 1),
      close: Decimal.parse('$i.5'),
      volume: i.isEven ? null : Decimal.fromInt(i),
    );

    test(
      'write keeps the newest limit candles, read returns them ordered',
      () async {
        final cache = DriftCandleCache(db, limit: 3);
        await cache.write(instrument, Interval.m1, [
          for (var i = 0; i < 5; i++) candle(i),
        ]);
        final read = await cache.read(instrument, Interval.m1);
        expect(read.map((c) => c.open.toBigInt().toInt()), [2, 3, 4]);
        expect(read.first.volume, isNull);
        expect(read[1].volume, Decimal.fromInt(3));
      },
    );

    test('entries are keyed by source, symbol and interval', () async {
      final cache = DriftCandleCache(db);
      await cache.write(instrument, Interval.m1, [candle(1)]);
      await cache.write(instrument, Interval.h1, [candle(2), candle(3)]);
      expect(await cache.read(instrument, Interval.m1), hasLength(1));
      expect(await cache.read(instrument, Interval.h1), hasLength(2));
      expect(
        await cache.read(
          instrument.copyWith(sourceId: 'coingecko'),
          Interval.m1,
        ),
        isEmpty,
      );
    });

    test('evict drops entries older than maxAge', () async {
      final cache = DriftCandleCache(db);
      await cache.write(instrument, Interval.m1, [candle(1)]);
      await cache.evict(
        maxAge: const Duration(hours: 24),
        now: DateTime.now().toUtc().add(const Duration(hours: 25)),
      );
      expect(await cache.read(instrument, Interval.m1), isEmpty);
    });
  });

  group('DriftSettingsStore', () {
    test('read / write / delete / watch', () async {
      final store = DriftSettingsStore(db);
      final seen = <String?>[];
      final sub = store.watch('k').listen(seen.add);
      expect(await store.read('k'), isNull);
      await store.write('k', 'v1');
      await store.write('k', 'v2');
      expect(await store.read('k'), 'v2');
      await store.delete('k');
      expect(await store.read('k'), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, isNull);
      expect(seen, contains('v2'));
      await sub.cancel();
    });
  });
}
