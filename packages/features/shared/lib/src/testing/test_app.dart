import 'package:features_shared/l10n/generated/shared_localizations.dart';
import 'package:features_shared/src/providers/market_data_source.dart';
import 'package:features_shared/src/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

/// A `MaterialApp` with the app theme, localizations and Riverpod scope,
/// for widget and golden tests of features.
Widget testApp({
  required Widget home,
  required List<Override> overrides,
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
}) => ProviderScope(
  retry: noRetry,
  overrides: overrides,
  child: MaterialApp(
    theme: buildTradeLensTheme(brightness),
    locale: locale,
    localizationsDelegates: SharedLocalizations.localizationsDelegates,
    supportedLocales: SharedLocalizations.supportedLocales,
    home: home,
  ),
);
