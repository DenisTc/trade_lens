import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'about_info.g.dart';

/// One data source as listed on the About screen.
@immutable
final class SourceTerms {
  const SourceTerms({
    required this.name,
    required this.termsUrl,
    required this.attribution,
  });

  final String name;
  final Uri termsUrl;
  final String attribution;
}

/// Static facts for the About screen. The check date is the day the terms
/// were last read by a human (spec: "дата последней проверки").
@immutable
final class AboutInfo {
  const AboutInfo({
    required this.sources,
    required this.termsCheckedOn,
    required this.privacyPolicyUrl,
    required this.termsOfUseUrl,
    required this.repositoryUrl,
    required this.version,
    this.installSource,
  });

  final List<SourceTerms> sources;
  final DateTime termsCheckedOn;
  final Uri privacyPolicyUrl;
  final Uri termsOfUseUrl;
  final Uri repositoryUrl;
  final String version;

  /// Attribution parameters of the install (deferred deep link, day 7).
  final String? installSource;
}

/// Overridden by the app with real version and attribution values.
@Riverpod(keepAlive: true)
AboutInfo aboutInfo(Ref ref) => AboutInfo(
  sources: [
    SourceTerms(
      name: 'Binance',
      termsUrl: Uri.parse('https://www.binance.com/en/terms'),
      attribution: 'Data: Binance',
    ),
    SourceTerms(
      name: 'Binance.US',
      termsUrl: Uri.parse('https://www.binance.us/terms-of-use'),
      attribution: 'Data: Binance.US',
    ),
    SourceTerms(
      name: 'CoinGecko',
      termsUrl: Uri.parse('https://www.coingecko.com/en/api_terms'),
      attribution: 'Powered by CoinGecko',
    ),
  ],
  termsCheckedOn: DateTime.utc(2026, 9, 8),
  privacyPolicyUrl: Uri.parse(
    'https://denistc.github.io/trade_lens/privacy-policy',
  ),
  termsOfUseUrl: Uri.parse('https://denistc.github.io/trade_lens/terms-of-use'),
  repositoryUrl: Uri.parse('https://github.com/DenisTc/trade_lens'),
  version: '0.1.0',
);
