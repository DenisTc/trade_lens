import 'package:data_market/src/http/spki_pinning.dart';

/// Leaf-certificate SPKI pins, captured 2026-09-08 with
/// `openssl s_client -connect <host>:443 | openssl x509 -pubkey`.
///
/// Known compromise (ADR-0002): we do not control these keys. Dart's
/// `validateCertificate` only exposes the leaf, so intermediate pins cannot
/// serve as backups; when a host rotates its key the app fails closed until
/// an update ships. Keep the previous pin next to the current one after
/// each rotation.
///
/// Certificate expiry as observed: api.binance.com 2027-01-09,
/// data-api.binance.vision 2027-03-03, api.binance.us 2027-03-18,
/// api.anthropic.com 2026-10-22, api.coingecko.com 2026-11-29.
const tradeLensPins = PinSet({
  'api.binance.com': {'/Y6BOeqMgXS6wjqk6emFs+Y+HWkIXO2R8Dox5VO1YT0='},
  'data-api.binance.vision': {'JNLtUB7spNN4Y10o3/p3kX/ksvhEV55uHfpAMpZmPeg='},
  'api.binance.us': {'is3VllVjJf3Ikd9CV8htIqRE5xtW29BM0kjMb0jAWa4='},
  'api.anthropic.com': {'yzfNb1bRcNF+H1Fts441Vj0MIuuxepdWKmqKJ/bVV6U='},
});
