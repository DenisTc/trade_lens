# TradeLens · День 2: источники данных Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Доменные сущности рынка, интерфейс `MarketDataSource` с двумя REST-реализациями (Binance Global/US, CoinGecko), region resolver с различением 451 и таймаута, SPKI-pinning для Dio и Sentry-фильтр. Всё покрыто unit-тестами на записанных фикстурах, живой сети в тестах нет.

**Architecture:** `domain` держит сущности (freezed, Decimal) и интерфейс. `data_market` реализует его поверх Dio; парсеры чистые функции; лимитер Binance учитывает вес по заголовку `x-mbx-used-weight-1m`; resolver проверяет цепочку кандидатов через `SourceProbe` (REST ping + WS-хендшейк) и кэширует результат с TTL 24 ч. Пиннинг реализован в `validateCertificate` адаптера Dio, SPKI извлекается собственным DER-парсером.

**Tech Stack:** freezed 4 / freezed_annotation 3, dio 5.11, crypto 3, clock 1.1, fake_async, sentry_flutter 9.

**Spec:** `docs/spec/tradelens-prd-tid-v1.2.md`, разделы «Источники данных», «Гео-ограничения», «Условия источников», «Безопасность», «Тесты», «План по дням» → День 2.

## Global Constraints

- «Decimal … парсинг из строк биржи без double». В domain `double` запрещён тестом.
- «Различаем два случая. 451 это подтверждённое региональное ограничение … Таймаут или 5xx это недоступность … повторяет через 5 с, потом переходит дальше».
- «WS-хендшейк с подпиской на один miniTicker и таймаутом 3 с. REST 200 при мёртвом WS не считается успехом».
- «Результат кэшируется на 24 ч».
- CoinGecko: «timestamp там это время закрытия свечи, адаптер приводит его к openTime вычитанием гранулярности»; «Опрос раз в 60 с»; capabilities без стакана, ленты, объёма и интервалов.
- Binance: «На 429 читать Retry-After и ждать, на 418 остановить запросы до истечения бана».
- Pinning: «через IOHttpClientAdapter.validateCertificate … badCertificateCallback не подходит». Тест: «доверенный сертификат с чужим пином отклоняется».
- «Сетевые тесты используют записанные фикстуры из test/fixtures».
- Sentry: «фильтр breadcrumbs по URL, чтобы ключ не утёк».

---

### Task 1: Домен рынка (`packages/domain`)

**Files:** `lib/domain.dart`, `lib/src/market/{asset,instrument,quote,candle,order_book,trade,capabilities,market_error,market_data_source}.dart`, `lib/src/market/default_assets.dart`, `test/interval_test.dart`, `test/default_assets_test.dart`

**Produces:**
- `Asset(id, symbol, name)`; `defaultAssets` — 20 активов.
- `Instrument(sourceId, symbol, base: Asset, quote)`; value equality (ключ family-провайдеров).
- `Quote(instrument, price, change24hPct?, at)`; `Candle(openTime, open, high, low, close, volume?)`.
- `enum Interval { m1, m15, h1, d1, auto }` с `duration` (у `auto` null) и `binanceCode`.
- `OrderBookLevel(price, qty)`, `OrderBookSnapshot(instrument, bids, asks, at)`, `Trade(...)`.
- `Capabilities(orderBook, trades, klineStream, volume, intervals)`.
- `sealed class MarketError`: `RegionBlocked(sourceId)`, `Unavailable(sourceId, reason)`, `RateLimited(retryAfter)`, `QuotaExhausted`, `NetworkFailure`, `ParseFailure(message)`.
- `abstract interface class MarketDataSource` по спеке; REST-методы возвращают `Result<T, MarketError>`.

- [x] Тест: `Interval.m15.duration == 15 min`, `Interval.auto.duration == null`; `defaultAssets.length == 20`, id уникальны, `Instrument` равны по значению.
- [x] Реализация, `melos run generate`, тесты зелёные, коммит `feat(domain): market entities and MarketDataSource`.

### Task 2: HTTP-инфраструктура (`packages/data_market/lib/src/http`)

**Files:** `spki_pinning.dart`, `pinned_adapter.dart`, `retry_interceptor.dart`, `dio_factory.dart`, `test/http/spki_pinning_test.dart`, `test/http/retry_interceptor_test.dart`, `test/fixtures/certs/*.der`

**Produces:**
- `String spkiSha256(Uint8List certificateDer)` → base64 SHA-256 SubjectPublicKeyInfo.
- `class PinSet { const PinSet(Map<String, Set<String>> pinsByHost); bool matches(String host, String pin); bool covers(String host); }`
- `bool validatePinnedCertificate(PinSet pins, X509Certificate? cert, String host)` — хосты без пинов пропускаются, хосты с пинами требуют совпадения.
- `Dio createDio({required Uri baseUrl, PinSet? pins, Logger? logger, Duration timeout})`.
- `const tradeLensPins = PinSet({...})` — пины сняты 08.09.2026, дата в комментарии.

- [x] Тесты: пин фикстуры `api.binance.com.der` равен значению из openssl; EC-ключ `api.anthropic.com.der` парсится; чужой пин → false; хост без пинов → true; retry: 2 повтора на 503, ноль на 451/429.
- [x] Коммит `feat(data_market): SPKI pinning adapter and retry interceptor`.

### Task 3: Binance REST (`lib/src/binance`)

**Files:** `binance_hosts.dart`, `binance_parsers.dart`, `binance_request_queue.dart`, `binance_rest_client.dart`, `binance_market_data_source.dart`, tests + фикстуры `ticker_24hr.json`, `klines_1m.json`.

**Produces:**
- `BinanceHosts.global / vision / us` (`rest`, `ws`, `sourceId`).
- `Quote parseTicker24h(Map<String, Object?> json, Instrument i)`, `Candle parseKline(List<Object?> row)`.
- `BinanceRequestQueue(clock, limitPerMinute: 6000, softLimit: 5000)`: `Future<Response<T>> run<T>(int weight, Future<Response<T>> Function() call)`; сериализует вызовы, читает `x-mbx-used-weight-1m`, при `429` ждёт `Retry-After`, при `418` блокирует до истечения бана.
- `BinanceRestClient(dio, queue)`: `ping()`, `ticker24h(List<String> symbols)`, `klines(symbol, Interval, limit)`.
- `BinanceMarketDataSource(client, hosts, assets)`: `instrumentFor` → `BASEQUOTE`; стримы бросают `StateError` до дня 3.

- [x] Тесты: парсеры на фикстурах (Decimal-строки один в один); очередь с fake_async: 429 → пауза на Retry-After, 418 → отказ до конца бана, softLimit → ожидание до следующей минуты; клиент через fake `HttpClientAdapter`.
- [x] Коммит `feat(data_market): Binance REST source with weight-aware queue`.

### Task 4: CoinGecko (`lib/src/coingecko`)

**Files:** `coingecko_ids.dart`, `coingecko_parsers.dart`, `coingecko_rest_client.dart`, `coingecko_market_data_source.dart`, tests + фикстуры.

**Produces:**
- `coinGeckoIdFor(Asset)`; `Duration ohlcGranularity(int days)` (1–2 → 30 мин, 3–30 → 4 ч, иначе 4 дня).
- `List<Candle> parseOhlc(List rows, Duration granularity)` — `openTime = ts − granularity`, `volume == null`.
- `CoinGeckoMarketDataSource`: `quotes` батчем по всем id; `klines(_, Interval.auto)` → `days=1`; `quoteStream` — опрос раз в 60 с через `clock`; 429 → `QuotaExhausted`; `attribution == 'Powered by CoinGecko'`.

- [x] Тесты: парсеры; `quoteStream` с fake_async выдаёт котировки на 0 с и 60 с; 429 → `QuotaExhausted`.
- [x] Коммит `feat(data_market): CoinGecko fallback source`.

### Task 5: Region resolver (`lib/src/region`)

**Files:** `source_probe.dart`, `http_source_probe.dart`, `ws_handshake.dart`, `region_resolver.dart`, `resolution_cache.dart`, tests.

**Produces:**
- `enum ProbeOutcome { ok, regionBlocked, unavailable }`; `abstract interface class SourceProbe { Future<ProbeOutcome> probe(SourceCandidate c); }`.
- `SourceCandidate(sourceId, restPing: Uri, wsHandshake: Uri?)`.
- `typedef WsHandshake = Future<bool> Function(Uri url, Duration timeout)`; `ioWsHandshake` на `dart:io`.
- `HttpSourceProbe(dio, wsHandshake)`: 200 + WS ок → ok; 451 → regionBlocked; таймаут/5xx/WS-таймаут → unavailable.
- `RegionResolver(probe, candidates, cache, clock, retryDelay: 5 s, ttl: 24 h)`: `Future<Resolution> resolve({bool force})`; `Resolution(sourceId, reason: ResolutionReason {direct, regionBlocked, unavailable}, at)`.
- `ResolutionCache` интерфейс + `InMemoryResolutionCache`.

- [x] Тесты (fake_async): 451 → следующий кандидат без ожидания; unavailable → повтор через 5 с, потом следующий; всё недоступно → CoinGecko с `reason.unavailable`; кэш в TTL не пробует; `force` пробует.
- [x] Коммит `feat(data_market): region resolver with 451 vs timeout semantics`.

### Task 6: Sentry-фильтр и логгер

**Files:** `packages/core/lib/src/logger.dart`, `apps/mobile/lib/observability/sentry_filters.dart`, `apps/mobile/lib/main.dart`, `apps/mobile/test/sentry_filters_test.dart`

- [x] `core`: `abstract interface class Logger { debug/info/warn/error }`, `PrintLogger`, `NoopLogger`.
- [x] `sanitizeBreadcrumb(Breadcrumb)`: для URL с `api.anthropic.com` обрезает query и заголовки, удаляет `Authorization`/`x-api-key` из data; тест.
- [x] `main.dart`: `SentryFlutter.init` только если `SENTRY_DSN` непустой, `beforeBreadcrumb: sanitizeBreadcrumb`.
- [x] Коммит `feat(app): Sentry with breadcrumb sanitizer`.

### Task 7: ADR, Codex-ревью, merge

- [x] `docs/decisions/0002-region-fallback-and-pinning.md`: цепочка источников, что дала проверка хостов binance.vision (08.09.2026: все три хоста отвечают 200 из региона разработчика, US-регион требует VPN — открытый пункт), компромисс pinning без бэкенда (только leaf-пины, ротация ломает до обновления).
- [x] `codex exec` ревью, исправления, `melos run format/analyze/test`, merge `--no-ff` в `develop`, push.
