import 'dart:async';

import 'package:features_settings/src/settings_screen.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// System language or one of the bundled locales.
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final current = ref.watch(appLocaleSettingProvider).value;
    final options = <Locale?>[null, ...SharedLocalizations.supportedLocales];
    final t = context.tokens;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.language)),
      body: RadioGroup<String>(
        groupValue: current?.languageCode ?? 'system',
        onChanged: (code) {
          if (code == null) return;
          unawaited(
            ref
                .read(appLocaleSettingProvider.notifier)
                .choose(code == 'system' ? null : Locale(code)),
          );
        },
        child: ListView(
          padding: const EdgeInsets.only(top: 8),
          children: [
            Divider(color: t.line),
            for (final locale in options)
              RadioListTile<String>(
                key: Key('language_${locale?.languageCode ?? 'system'}'),
                value: locale?.languageCode ?? 'system',
                controlAffinity: ListTileControlAffinity.trailing,
                shape: Border(bottom: BorderSide(color: t.line)),
                title: Text(
                  locale == null ? l10n.languageSystem : languageName(locale),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
