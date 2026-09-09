# TradeLens · День 5: портфель, хранилище, локали Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Портфель с ручным вводом позиций и оценкой по живой цене, Drift с четырьмя таблицами и реальной миграцией v1→v2, офлайн-оценка «на 12:40» по `last_quotes`, кэш свечей, локали en/ru через ARB и intl, токены тёмной темы одним файлом, экран настроек с ручным выбором источника и экран «О приложении», privacy policy и terms на GitHub Pages.

**Architecture:** `domain` получает `Position`, чистую функцию `PortfolioValuation.compute` и интерфейсы `PortfolioRepository`, `LastQuoteStore`, `CandleCache`, `SettingsStore`. `data_local` реализует их на Drift (Decimal хранится как TEXT). Провайдеры интерфейсов добавляются в `features_shared`, приложение переопределяет их Drift-реализациями. `features/portfolio` и `features/settings` только UI + Notifier-ы. Локализация живёт в `features_shared` (`SharedLocalizations`), фичи берут строки из неё.

**Tech Stack:** drift 2.34 + drift_dev schema tooling, drift_flutter, intl 0.20, flutter_localizations gen-l10n, url_launcher, package_info_plus.

**Spec:** `docs/spec/tradelens-prd-tid-v1.2.md`, разделы «Хранилище и портфель», «Функции» → Портфель, Локализация, Тёмная тема, «Условия источников» → Как это отражено в продукте, «Сторы, privacy», «План по дням» → День 5.

## Global Constraints

- «Позиции в Drift, оценка по живой цене, суммарный PnL. Decimal-арифметика, никаких double в деньгах».
- «Оценка считается только по котировке в той же валюте … Если активный источник не даёт сопоставимой цены, оценка показывается как недоступная».
- «Офлайн-оценка портфеля считается по `last_quotes` с подписью «на 12:40» … Без сохранённой котировки оценка недоступна».
- «`PortfolioValuation` в domain как чистая функция … Тестируется без Drift и без сети».
- «Миграции: схема стартует с v1, а в день 5 добавляется реальная v2 (поле `note` у позиции) с тестом миграции через drift_dev schema tooling».
- «Кэш свечей: последние 500 на источник, инструмент и интервал … Сеть подменяет кэш, а не ждёт его». «Кэш ключуется по `sourceId + instrument + interval`».
- «en, ru через flutter_localizations + ARB. Числа и даты через intl по локали». «Тёмная тема: системная, дизайн-токены одним файлом».
- «Источник можно выбрать вручную» (настройки), «экран «О приложении»: источники со ссылками на условия, дата последней проверки, описание потоков данных, ссылка на privacy policy».

---

### Task 1: домен портфеля
- [ ] `Position`, `PositionValuation`, `PortfolioValuation.compute(positions, quotesByKey, asOf, {live})`, интерфейсы `PortfolioRepository`, `LastQuoteStore`, `CandleCache`, `SettingsStore`; тесты: PnL, недоступная котировка, чужая валюта котировки, пустой портфель.

### Task 2: `data_local` на Drift
- [ ] Таблицы `positions`, `candle_cache`, `last_quotes`, `settings`; схема v1 → dump; v2 с `note` → dump; `drift_dev schema generate` → тест миграции с сохранностью данных; DAO-реализации интерфейсов; тесты на in-memory БД.

### Task 3: провайдеры и запись кэшей
- [ ] `features_shared`: провайдеры интерфейсов хранилища, `portfolioValuationProvider` (live котировки → fallback на `last_quotes` с `asOf`), запись `last_quotes` из `quoteProvider` с троттлингом, `candlesProvider` читает кэш первым и пишет после REST.

### Task 4: локали и тема
- [ ] `SharedLocalizations` (ARB en/ru) в `features_shared`, `flutter gen-l10n` в `melos run generate`; `TradeLensTokens` ThemeExtension одним файлом; `formatPrice`/`formatChangePct` через intl по локали; строки экранов из l10n.

### Task 5: экраны портфеля и настроек
- [ ] `features/portfolio`: список позиций, итог, PnL, «на HH:mm» в офлайне, добавление и удаление; `features/settings`: выбор источника (auto / binance / binance_us / coingecko) с сохранением, «Проверить источник», раздел «О приложении» (источники, дата проверки, потоки данных, privacy, версия); маршруты `/portfolio`, `/settings`; нижняя навигация в приложении.

### Task 6: документы и релиз
- [ ] `docs/privacy-policy.md`, `docs/terms-of-use.md` для GitHub Pages; скриншоты; ADR-0004 (хранилище и миграции); Codex-ревью; merge, `main`, тег `v0.1.0-day5`.
