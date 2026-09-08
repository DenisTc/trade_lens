import 'dart:io';
import 'dart:typed_data';

import 'package:data_market/data_market.dart';
import 'package:test/test.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/certs/$name').readAsBytesSync();

void main() {
  // Values computed independently with
  // `openssl x509 -pubkey | openssl pkey -pubin -outform der | sha256 | base64`
  const binancePin = '/Y6BOeqMgXS6wjqk6emFs+Y+HWkIXO2R8Dox5VO1YT0=';
  const anthropicPin = 'yzfNb1bRcNF+H1Fts441Vj0MIuuxepdWKmqKJ/bVV6U=';

  group('spkiSha256', () {
    test('matches openssl for an RSA leaf (api.binance.com)', () {
      expect(spkiSha256(_fixture('api.binance.com.der')), binancePin);
    });

    test('matches openssl for an EC leaf (api.anthropic.com)', () {
      expect(spkiSha256(_fixture('api.anthropic.com.der')), anthropicPin);
    });

    test('rejects bytes that are not a certificate', () {
      expect(
        () => spkiSha256(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });
  });

  group('validatePinnedCertificate', () {
    const pins = PinSet({
      'api.binance.com': {binancePin},
    });

    test('accepts the pinned key for a pinned host', () {
      expect(
        pins.matches(
          'api.binance.com',
          spkiSha256(_fixture('api.binance.com.der')),
        ),
        isTrue,
      );
    });

    test('rejects a trusted certificate whose key is not pinned', () {
      // The Anthropic leaf is a perfectly valid, trusted certificate,
      // but its key is not the one we pinned for api.binance.com.
      expect(
        pins.matches(
          'api.binance.com',
          spkiSha256(_fixture('api.anthropic.com.der')),
        ),
        isFalse,
      );
    });

    test('passes hosts that have no pins', () {
      expect(validatePinnedCertificate(pins, null, 'example.com'), isTrue);
    });

    test('fails closed when the certificate is missing for a pinned host', () {
      expect(validatePinnedCertificate(pins, null, 'api.binance.com'), isFalse);
    });
  });

  test('shipping pin set covers every pinned host', () {
    for (final host in [
      'api.binance.com',
      'data-api.binance.vision',
      'api.binance.us',
      'api.anthropic.com',
    ]) {
      expect(tradeLensPins.covers(host), isTrue, reason: host);
      expect(tradeLensPins.pinsFor(host), isNotEmpty, reason: host);
    }
  });
}
