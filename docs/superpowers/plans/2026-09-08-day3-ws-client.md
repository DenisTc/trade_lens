# TradeLens · День 3: сокет и список пар Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Пакет `ws_client` с реестром подписок, батчингом команд, реконнектом и детектом тишины; стримы Binance (miniTicker, kline, стакан top-10 снапшотом, лента); список пар на Riverpod 3 с family-провайдерами по инструменту.

**Architecture:** `WsClient` держит одно соединение на источник поверх абстрактного `WsTransport` (IO-реализация и фейк для тестов). Реестр «стрим → счётчик слушателей» решает, что должно быть подписано; изменения за 250 мс схлопываются в один `SUBSCRIBE`/`UNSUBSCRIBE`; исходящие идут через ограничитель 4 сообщения/с. Реконнект с экспоненциальной задержкой и джиттером, детект тишины 60 с, heartbeat-подписка на ликвидный miniTicker. `data_market` маппит WS-сообщения в доменные события; добор свечей после реконнекта идёт по REST от последней `openTime`. Провайдеры интерфейсов живут в `features/shared` (ADR-0003), реализации подключаются через override в приложении.

**Tech Stack:** dart:io WebSocket, clock, fake_async, Riverpod 3.4 codegen, flutter_riverpod.

**Spec:** `docs/spec/tradelens-prd-tid-v1.2.md`, разделы «WebSocket-слой», «Источники данных», «Riverpod: правила», «Функции» → Список пар, «План по дням» → День 3.

## Global Constraints

- «Одно соединение на источник, комбинированный стрим … одна очередь с ограничителем 4 сообщения в секунду … Изменения реестра за 250 мс собираются в один SUBSCRIBE и один UNSUBSCRIBE».
- «Подписка на бирже открывается на первом слушателе, закрывается на последнем с задержкой 2 с».
- «если 60 с не было ни одного data-кадра по активным подпискам, соединение считается мёртвым и пересоздаётся. Для тихих пар держим подписку на один miniTicker ликвидной пары как heartbeat».
- «Реконнект с экспоненциальной задержкой 1, 2, 4, 8, максимум 30 с, с джиттером … После реконнекта восстанавливаются все подписки из реестра, свечи добирают пропуск по REST от последней известной openTime».
- «`@depth10@100ms` отдаёт полный top-10 … локальное состояние заменяется целиком».
- «в фоне соединение закрывается через 30 с, при возврате открывается заново».
- «Provider стрима при dispose реально снимает слушателя с реестра, тест на это обязателен».
- Riverpod: «Стримы биржи это family-провайдеры с параметром instrument … счётчик реестра уменьшается только после ухода последнего потребителя».
- Список пар: «20 пар из конфига, цена, изменение 24 ч, мини-спарклайн из последних 60 тиков. Поиск по названию».

---

### Task 1: `ws_client`

**Files:** `lib/ws_client.dart`, `lib/src/transport.dart` (`WsTransport`, `WsConnection`, `IoWsTransport`), `lib/src/outbound_limiter.dart`, `lib/src/subscription_registry.dart`, `lib/src/backoff.dart`, `lib/src/ws_client.dart`, `lib/src/coalesce.dart`; tests `test/support/fake_transport.dart`, `test/subscription_registry_test.dart`, `test/outbound_limiter_test.dart`, `test/backoff_test.dart`, `test/ws_client_test.dart`, `test/coalesce_test.dart`.

**Produces:**
- `abstract interface class WsTransport { Future<WsConnection> connect(Uri url); }`, `WsConnection { Stream<String> messages; void send(String); Future<void> close(); }`.
- `OutboundLimiter(maxPerSecond: 4, clock)`: `Future<void> acquire()`.
- `SubscriptionRegistry`: `int add(String stream)`, `int remove(String stream)`, `Set<String> get wanted`, `int count(String)`.
- `Backoff(base: 1s, max: 30s, random)`: `Duration next()`, `void reset()`; джиттер ±20 %.
- `WsClient({transport, url, clock, logger, silenceTimeout: 60s, batchWindow: 250ms, unsubscribeDelay: 2s, heartbeatStream})`: `Stream<WsMessage> subscribe(String stream)`, `Stream<WsConnectionState> get states`, `WsConnectionState get state`, `void suspend()`, `void resume()`, `Future<void> dispose()`, `int listenerCount(String)`, `Set<String> get serverSubscriptions`.
- `WsMessage(stream, data)`; `enum WsConnectionState { idle, connecting, connected, reconnecting, suspended }`.
- `Stream<List<T>> coalesce<T>(Stream<T>, Duration window)`: собирает события за окно (16 мс) в один список.

- [x] Тесты (fake_async, FakeTransport с ручным управлением): первый слушатель открывает соединение и шлёт один SUBSCRIBE с двумя стримами, добавленными в пределах 250 мс; второй слушатель того же стрима не шлёт команду; отписка последнего шлёт UNSUBSCRIBE через 2 с, а повторная подписка в это окно отменяет её; ограничитель пропускает 4 команды в секунду; обрыв соединения → реконнект через 1, 2, 4 с (Random зафиксирован), после успеха SUBSCRIBE со всеми стримами реестра; тишина 60 с → пересоздание; heartbeat всегда в подписках, пока есть хотя бы один слушатель; `suspend` закрывает без реконнекта, `resume` открывает; сообщения доставляются по имени стрима.
- [x] Коммит `feat(ws_client): connection with registry, batching, reconnect and silence detection`.

### Task 2: Binance-стримы в `data_market`

**Files:** `lib/src/binance/binance_streams.dart` (имена стримов, парсеры miniTicker/depth10/trade), `binance_market_data_source.dart` (стримы через `WsClient`, kline с добором), tests + фикстуры `test/fixtures/binance/ws/*.json`.

**Produces:**
- `String miniTickerStream(symbol)`, `klineStream(symbol, Interval)`, `depth10Stream(symbol)`, `tradeStream(symbol)`.
- `Quote parseMiniTicker(Map data, Instrument)`: изменение за 24 ч считается как `(c − o) / o × 100` на Decimal.
- `OrderBookSnapshot parseDepth10(Map data, Instrument, DateTime at)`, `Trade parseTradeEvent(Map data, Instrument)`.
- `BinanceMarketDataSource({..., WsClient? ws, BinanceRestClient client})`: `quoteStream` объединяет miniTicker-подписки инструментов; `klineStream` слушает `@kline_<iv>` и после каждого повторного `connected` дозапрашивает REST `klines(startTime: lastOpenTime)` и эмитит добор перед живыми свечами; `orderBookStream`, `tradeStream`.

- [x] Тесты: парсеры на фикстурах; квота-стрим для 2 инструментов открывает 2 подписки; добор после реконнекта вызывает REST с `startTime` последней свечи и эмитит недостающие.
- [x] Коммит `feat(data_market): Binance streams over ws_client with kline backfill`.

### Task 3: `features/shared` и ADR-0003

**Files:** `packages/features/shared/pubspec.yaml`, `lib/features_shared.dart`, `lib/src/providers/market_data_source.dart`, `lib/src/providers/assets.dart`, `lib/src/providers/quotes.dart`, `lib/src/providers/connection.dart`, `lib/src/widgets/data_source_badge.dart`, `lib/src/widgets/async_value_view.dart`; `tooling/arch_test` allow-list; `docs/decisions/0003-provider-ownership.md`; tests.

**Produces:**
- `@Riverpod(keepAlive: true) Future<MarketDataSource> marketDataSource(Ref)` — бросает `UnimplementedError`, приложение переопределяет.
- `@Riverpod(keepAlive: true) List<Asset> assets(Ref)` → `defaultAssets`.
- `@riverpod Future<List<Instrument>> marketInstruments(Ref)`.
- `@riverpod Stream<Quote> quote(Ref, Instrument)` — family, autoDispose.
- `@riverpod class QuoteHistory extends _$QuoteHistory` family: последние 60 цен.
- `@Riverpod(keepAlive: true) Stream<WsConnectionState> connectionState(Ref)` — переопределяется приложением, по умолчанию `idle`.
- Виджеты: `DataSourceBadge`, `AsyncValueView<T>` с тремя состояниями явно.

- [x] Тест (спека): фейковый источник со счётчиком слушателей; два `ProviderContainer.listen` на один `quoteProvider(instrument)`; после отмены первого счётчик не меняется, после отмены второго и autoDispose падает до нуля.
- [x] Обновить `dependency_direction_test`: features → `features_shared` разрешён, `features_shared` не считается «соседней фичей».
- [x] Коммит `feat(features_shared): interface providers, ADR-0003`.

### Task 4: `features/markets` и приложение

**Files:** `packages/features/markets/lib/src/markets_screen.dart`, `pair_tile.dart`, `markets_search.dart`; `packages/chart/lib/src/sparkline.dart`; `apps/mobile/lib/di/market_di.dart` (сборка `WsClient`, `HttpSourceProbe`, `RegionResolver`, источников; override провайдеров), `apps/mobile/lib/app.dart`, `router.dart`; tests.

- [x] `MarketsScreen`: поиск по названию/символу, список `PairTile` (цена, изменение 24 ч цветом, спарклайн 60 тиков, три состояния AsyncValue), `DataSourceBadge` внизу, точка состояния соединения в шапке.
- [x] `Sparkline(values: List<double>)` в `chart` — CustomPainter без зависимостей.
- [x] Приложение: `marketOverrides()` возвращает overrides; `marketDataSource` = resolver → Binance (Global / vision / US хосты) с `WsClient` либо CoinGecko. Lifecycle: `AppLifecycleListener` → `suspend()` через 30 с в фоне, `resume()` при возврате.
- [x] Тесты: widget-тест списка с фейковым источником (три состояния, поиск), тест приложения с overrides.
- [x] Коммит `feat(markets): live pair list on Riverpod`.

### Task 5: Codex-ревью, merge

- [ ] `melos run format/analyze/test`, `codex exec` ревью, правки, merge `--no-ff` в `develop`, push.
