import 'package:features_shared/l10n/generated/shared_localizations.dart';
import 'package:flutter/widgets.dart';

extension SharedL10nX on BuildContext {
  SharedLocalizations get l10n => SharedLocalizations.of(this);

  /// Locale tag for `intl` formatting, e.g. `en_US`, `ru`.
  String get localeTag => Localizations.localeOf(this).toString();
}
