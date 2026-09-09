import 'dart:io';
import 'dart:typed_data';

import 'package:data_market/data_market.dart';
import 'package:test/test.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/certs/$name').readAsBytesSync();

/// Only [der] matters to the pin check.
final class _Cert implements X509Certificate {
  _Cert(this.der);

  @override
  final Uint8List der;

  @override
  Uint8List get sha1 => Uint8List(0);

  @override
  String get pem => '';

  @override
  String get subject => '';

  @override
  String get issuer => '';

  @override
  DateTime get startValidity => DateTime.utc(2026);

  @override
  DateTime get endValidity => DateTime.utc(2027);
}

void main() {
  const pins = PinSet({
    'api.anthropic.com': {'yzfNb1bRcNF+H1Fts441Vj0MIuuxepdWKmqKJ/bVV6U='},
  });

  SpkiPreflight preflight(
    Future<X509Certificate?> Function(String, int) handshake, {
    Duration ttl = const Duration(minutes: 10),
  }) => SpkiPreflight(pins: pins, ttl: ttl, handshake: handshake);

  test('a host without pins needs no handshake', () async {
    var calls = 0;
    final p = preflight((_, _) async {
      calls++;
      return null;
    });
    expect(await p.verify('example.com'), isTrue);
    expect(calls, 0);
  });

  test('accepts the pinned key and caches it for the TTL', () async {
    var calls = 0;
    final p = preflight((_, _) async {
      calls++;
      return _Cert(_fixture('api.anthropic.com.der'));
    });
    final start = DateTime.utc(2026, 9, 9, 12);
    expect(await p.verify('api.anthropic.com', now: start), isTrue);
    expect(
      await p.verify(
        'api.anthropic.com',
        now: start.add(const Duration(minutes: 9)),
      ),
      isTrue,
    );
    expect(calls, 1, reason: 'the second check is inside the TTL');
    expect(
      await p.verify(
        'api.anthropic.com',
        now: start.add(const Duration(minutes: 11)),
      ),
      isTrue,
    );
    expect(calls, 2, reason: 'the TTL expired, so it handshakes again');
  });

  test('rejects a trusted certificate whose key is not pinned', () async {
    final p = preflight((_, _) async => _Cert(_fixture('api.binance.com.der')));
    expect(await p.verify('api.anthropic.com'), isFalse);
  });

  test('fails closed when the handshake gives nothing or throws', () async {
    expect(
      await preflight((_, _) async => null).verify('api.anthropic.com'),
      isFalse,
    );
    expect(
      await preflight((_, _) async => throw const SocketException('down'))
          .verify('api.anthropic.com'),
      isFalse,
    );
  });

  test('a failed check is not cached', () async {
    var calls = 0;
    final p = preflight((_, _) async {
      calls++;
      return calls == 1 ? null : _Cert(_fixture('api.anthropic.com.der'));
    });
    expect(await p.verify('api.anthropic.com'), isFalse);
    expect(await p.verify('api.anthropic.com'), isTrue);
    expect(calls, 2);
  });
}
