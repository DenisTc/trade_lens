import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Public-key pinning by SubjectPublicKeyInfo hash, the same value
/// `openssl x509 -pubkey | openssl pkey -pubin -outform der | sha256` gives.
///
/// Why SPKI and not the whole certificate: a renewed certificate with the
/// same key keeps the pin valid, so routine renewals do not break the app.
/// Why not `badCertificateCallback`: it runs only for certificates that
/// already failed system validation; pinning must run on top of a
/// successful chain check, which is what `validateCertificate` gives.
final class PinSet {
  const PinSet(this._pinsByHost);

  final Map<String, Set<String>> _pinsByHost;

  bool covers(String host) => _pinsByHost.containsKey(host);

  bool matches(String host, String pin) =>
      _pinsByHost[host]?.contains(pin) ?? false;

  Set<String> pinsFor(String host) => _pinsByHost[host] ?? const {};
}

/// Base64 SHA-256 of the SubjectPublicKeyInfo inside a DER certificate.
///
/// Throws [FormatException] if the bytes are not an X.509 certificate.
String spkiSha256(Uint8List certificateDer) {
  final spki = extractSpki(certificateDer);
  return base64.encode(sha256.convert(spki).bytes);
}

/// The raw SubjectPublicKeyInfo TLV (tag + length + value) from a DER
/// certificate. Minimal ASN.1 walk, enough for X.509 v3:
///
/// ```text
/// Certificate ::= SEQUENCE {
///   tbsCertificate SEQUENCE {
///     [0] version OPTIONAL, serialNumber, signature, issuer,
///     validity, subject, subjectPublicKeyInfo, ...
///   }, ...
/// }
/// ```
Uint8List extractSpki(Uint8List der) {
  final certificate = _Tlv.read(der, 0);
  if (certificate.tag != _sequence) {
    throw const FormatException('certificate is not a SEQUENCE');
  }
  final tbs = _Tlv.read(der, certificate.valueStart);
  if (tbs.tag != _sequence) {
    throw const FormatException('tbsCertificate is not a SEQUENCE');
  }

  var offset = tbs.valueStart;
  var element = _Tlv.read(der, offset);
  if (element.tag == _explicitVersion) {
    offset = element.end;
    element = _Tlv.read(der, offset);
  }
  // serialNumber, signature, issuer, validity, subject
  for (var i = 0; i < 5; i++) {
    offset = element.end;
    element = _Tlv.read(der, offset);
  }
  if (element.tag != _sequence) {
    throw const FormatException('subjectPublicKeyInfo is not a SEQUENCE');
  }
  return Uint8List.sublistView(der, element.start, element.end);
}

/// Validates the leaf certificate's SPKI against [pins] when the host is
/// pinned. Unpinned hosts pass: pinning is an extra check for the hosts we
/// chose, not a global allow-list.
bool validatePinnedCertificate(
  PinSet pins,
  X509Certificate? certificate,
  String host,
) {
  if (!pins.covers(host)) return true;
  if (certificate == null) return false;
  try {
    return pins.matches(host, spkiSha256(certificate.der));
  } on FormatException {
    return false;
  }
}

const _sequence = 0x30;
const _explicitVersion = 0xA0;

final class _Tlv {
  const _Tlv({
    required this.tag,
    required this.start,
    required this.valueStart,
    required this.end,
  });

  final int tag;
  final int start;
  final int valueStart;
  final int end;

  // ignore: prefer_constructors_over_static_methods, reads from a buffer
  static _Tlv read(Uint8List bytes, int start) {
    if (start + 2 > bytes.length) {
      throw const FormatException('truncated DER element');
    }
    final tag = bytes[start];
    var cursor = start + 1;
    var length = bytes[cursor++];
    if (length & 0x80 != 0) {
      final lengthBytes = length & 0x7F;
      if (lengthBytes == 0 || lengthBytes > 4) {
        throw const FormatException('unsupported DER length');
      }
      length = 0;
      for (var i = 0; i < lengthBytes; i++) {
        if (cursor >= bytes.length) {
          throw const FormatException('truncated DER length');
        }
        length = (length << 8) | bytes[cursor++];
      }
    }
    final end = cursor + length;
    if (end > bytes.length) {
      throw const FormatException('DER element exceeds buffer');
    }
    return _Tlv(tag: tag, start: start, valueStart: cursor, end: end);
  }
}
