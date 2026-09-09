import 'package:features_settings/src/about_info.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sources with links to their terms, the date the terms were last
/// checked, what leaves the device, privacy policy, terms of use, install
/// source; the version centred at the bottom under the lens ring.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = context.localeTag;
    final theme = Theme.of(context);
    final t = context.tokens;
    final about = ref.watch(aboutInfoProvider).value ?? AboutInfo.defaults();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.about)),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 16,
        ),
        children: [
          GroupLabel(
            '${l10n.aboutDataSources} · '
            '${l10n.aboutTermsChecked(MoneyFormat.date(about.termsCheckedOn, locale: locale))}',
          ),
          for (final s in about.sources)
            SettingsRow(
              title: s.name,
              subtitle: '${s.attribution} · ${l10n.aboutSourceHint}',
              trailing: Icon(Icons.open_in_new, color: t.muted, size: 18),
              onTap: () => _open(s.termsUrl),
            ),
          GroupLabel(l10n.aboutDataFlows),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              l10n.aboutDataFlowsText,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ),
          Divider(color: t.line),
          SettingsRow(
            title: l10n.privacyPolicy,
            subtitle: _short(about.privacyPolicyUrl),
            trailing: Icon(Icons.open_in_new, color: t.muted, size: 18),
            onTap: () => _open(about.privacyPolicyUrl),
          ),
          SettingsRow(
            title: l10n.termsOfUse,
            subtitle: _short(about.termsOfUseUrl),
            trailing: Icon(Icons.open_in_new, color: t.muted, size: 18),
            onTap: () => _open(about.termsOfUseUrl),
          ),
          SettingsRow(
            title: l10n.aboutInstallSource,
            subtitle: about.installSource ?? l10n.aboutInstallSourceNone,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 8),
            child: Column(
              children: [
                LensRing(size: 28, color: t.accent),
                const SizedBox(height: 10),
                Text(l10n.appName, style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  l10n.version(about.version.isEmpty ? '…' : about.version),
                  key: const Key('about_version'),
                  style: TradeLensText.mono(
                    size: 12,
                    weight: FontWeight.w400,
                    color: t.muted,
                  ),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _open(about.repositoryUrl),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      _short(about.repositoryUrl),
                      style: TradeLensText.mono(
                        size: 11,
                        weight: FontWeight.w400,
                        color: t.muted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _short(Uri url) =>
      '${url.host}${url.path}'.replaceFirst(RegExp(r'/$'), '');

  Future<void> _open(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);
}
