import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeMarketDataSource source;
  late ProviderContainer container;
  late Instrument btc;

  setUp(() {
    source = FakeMarketDataSource();
    container = ProviderContainer(overrides: fakeOverrides(source: source));
    addTearDown(container.dispose);
    btc = source.instrumentFor(defaultAssets.first, 'USDT');
  });

  /// Lets Riverpod run its dispose pass and the stream its microtasks.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('registry counter drops only after the last consumer leaves', () async {
    final first = container.listen(quoteProvider(btc), (_, _) {});
    final second = container.listen(quoteProvider(btc), (_, _) {});
    await settle();
    expect(
      source.listenerCount(btc),
      1,
      reason: 'one provider, one socket sub',
    );

    first.close();
    await settle();
    expect(source.listenerCount(btc), 1, reason: 'second consumer keeps it');

    second.close();
    await settle();
    expect(source.listenerCount(btc), 0, reason: 'autoDispose released it');
  });

  test('quote provider emits AsyncData with the streamed price', () async {
    final values = <AsyncValue<Quote>>[];
    container.listen(quoteProvider(btc), (_, next) => values.add(next));
    await settle();
    source.emit(btc, '78000.5', change: '-1.5');
    await settle();

    final quote = values.last.value!;
    expect(quote.price, Decimal.parse('78000.5'));
    expect(quote.change24hPct, Decimal.parse('-1.5'));
  });

  test('a re-listener gets the remembered quote at once', () async {
    final first = container.listen(quoteProvider(btc), (_, _) {});
    await settle();
    source.emit(btc, '123');
    await settle();
    first.close();
    await settle();

    container.listen(quoteProvider(btc), (_, _) {});
    await settle();
    expect(
      container.read(quoteProvider(btc)).value?.price,
      Decimal.fromInt(123),
      reason: 'no spinner: the last price is replayed from the memo',
    );
  });

  test(
    'with a keep-alive grace the socket subscription survives a scroll',
    () async {
      final graced = ProviderContainer(
        retry: noRetry,
        overrides: fakeOverrides(
          source: source,
          quoteKeepAlive: const Duration(minutes: 1),
        ),
      );
      addTearDown(graced.dispose);
      final sub = graced.listen(quoteProvider(btc), (_, _) {});
      await settle();
      sub.close();
      await settle();
      expect(source.listenerCount(btc), 1, reason: 'kept alive for the grace');
    },
  );

  test('quote history keeps the last 60 prices', () async {
    container.listen(quoteHistoryProvider(btc), (_, _) {});
    await settle();
    for (var i = 0; i < 70; i++) {
      source.emit(btc, '$i');
    }
    await settle();

    final history = container.read(quoteHistoryProvider(btc));
    expect(history, hasLength(60));
    expect(history.first, Decimal.fromInt(10));
    expect(history.last, Decimal.fromInt(69));
  });

  test(
    'marketInstruments lists the catalog against the default quote',
    () async {
      final instruments = await container.read(
        marketInstrumentsProvider.future,
      );
      expect(instruments, hasLength(defaultAssets.length));
      expect(instruments.first.symbol, 'BTCUSDT');
    },
  );

  test('marketDataSource must be overridden', () {
    final bare = ProviderContainer();
    addTearDown(bare.dispose);
    expect(
      bare.read(marketDataSourceProvider.future),
      throwsUnimplementedError,
    );
  });
}
