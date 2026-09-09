import 'dart:io';

import 'package:data_market/src/http/spki_pinning.dart';

/// Checks a host's pin on a TLS handshake of its own, before any request
/// body is sent.
///
/// Why it exists: Dio's `validateCertificate` runs on the response, so by
/// the time a pin mismatch is noticed the request (and, for the Claude
/// client, the user's API key) has already left the device. A handshake
/// that carries no application data closes that window: the key is sent
/// only after a connection to the same host presented a pinned key. The
/// residual risk, an interception that behaves differently on the second
/// connection, is recorded in ADR-0002 together with the rest of the
/// pinning compromise.
final class SpkiPreflight {
  SpkiPreflight({
    required PinSet pins,
    Duration ttl = const Duration(minutes: 1),
    Duration timeout = const Duration(seconds: 8),
    Future<X509Certificate?> Function(String host, int port)? handshake,
  }) : this._(pins, ttl, timeout, handshake ?? _connect);

  SpkiPreflight._(this._pins, this.ttl, this.timeout, this._handshake);

  final PinSet _pins;

  /// How long a successful check is trusted before the next handshake.
  /// Short on purpose: it exists to share one probe between the calls of a
  /// single summary, not to trust a network across time.
  final Duration ttl;
  final Duration timeout;
  final Future<X509Certificate?> Function(String host, int port) _handshake;

  final _checked = <String, DateTime>{};

  /// True when [host] is unpinned (nothing to check) or presented a pinned
  /// key; false when the certificate does not match or cannot be read.
  Future<bool> verify(String host, {int port = 443, DateTime? now}) async {
    if (!_pins.covers(host)) return true;
    final at = now ?? DateTime.now();
    final last = _checked[host];
    if (last != null && at.difference(last) < ttl) return true;
    final X509Certificate? certificate;
    try {
      certificate = await _handshake(host, port).timeout(timeout);
    } on Object {
      return false;
    }
    if (certificate == null) return false;
    if (!validatePinnedCertificate(_pins, certificate, host)) return false;
    _checked[host] = at;
    return true;
  }

  static Future<X509Certificate?> _connect(String host, int port) async {
    final socket = await SecureSocket.connect(host, port);
    final certificate = socket.peerCertificate;
    await socket.close();
    socket.destroy();
    return certificate;
  }
}
