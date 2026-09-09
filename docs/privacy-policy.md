---
title: TradeLens Privacy Policy
---

# TradeLens Privacy Policy

Effective: 9 September 2026. Applies to the TradeLens mobile application
published by Denis Tciapalo ("we").

TradeLens shows public cryptocurrency market data and keeps a manual
portfolio on your device. It has no accounts, no wallets and no trading.
There is no TradeLens server: the app talks directly to the services below.

## What the app stores on your device

- Your portfolio positions (asset, quantity, average price, note).
- A cache of market data (candles and last prices) for up to 24 hours.
- Settings: chosen data source and the cached result of the region check.
- Planned (not in the current build): install attribution parameters,
  your consent to the AI summary feature and your Anthropic API key in the
  platform secure storage (Keychain on iOS, Keystore on Android).

None of this is sent to us. Deleting the app deletes it.

## Services the app talks to

| Service | What is sent | Why |
|---|---|---|
| Binance / Binance.US (public market data endpoints) | Requests for prices, candles, order book and trades of the pairs you view; your IP address as with any internet request | Live market data |
| CoinGecko (Demo API) | Requests for prices and candles; your IP address; a demo API key shared by all installs | Fallback market data when an exchange is unavailable in your region |
| Sentry | Crash reports: stack trace, device model, OS version, app version. URLs are stripped of query strings; API keys are never included | Stability |

### Planned integrations (not in the current build)

These will be added in later versions and this policy will be updated when
they ship:

| Service | What would be sent | Why |
|---|---|---|
| Anthropic (api.anthropic.com) | Only when you tap "Move summary": candles and order book of the current pair, together with **your own** API key | AI summary of price movement |
| Firebase Remote Config | Firebase installation identifier, app version, device locale | Server-driven "Insights" screen and feature flags |
| OneSignal | Push token, an optional tag with your favourite pair | Push notifications, only after you allow them |
| AppsFlyer | Install identifier and OneLink parameters. IDFA collection is disabled; no advertising tracking | Deferred deep link on first launch and the "Install source" line in About |

The market data services see the same request any browser would send. We
do not share, sell or match any data with third parties.

## AI summary (planned)

The "Move summary" feature will be off until you enter your own Anthropic API
key and accept a consent screen that lists exactly what is sent. The
request goes from your device to api.anthropic.com only; Anthropic's
handling of API requests is governed by their
[privacy policy](https://www.anthropic.com/privacy). The summary is not
financial advice.

## Your choices

- Choose the data source in Settings, including the REST-only fallback.
- Delete the app to remove all local data.

## Children

TradeLens is not directed at children under 16.

## Changes

We will update this page and the effective date when anything above
changes. The current version is always at
<https://denistc.github.io/trade_lens/privacy-policy>.

## Contact

Denis Tciapalo · <https://github.com/DenisTc/trade_lens/issues>
