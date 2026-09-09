import 'dart:async';

import 'package:features_settings/src/about_info.dart';
import 'package:features_settings/src/source_choice.dart';

import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Data-source choice plus the About section: sources with links to their
/// terms, the date the terms were last checked, what leaves the device,
/// privacy policy, terms of use, install source, version.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.onCheckSource});

  /// "Check source now" for the automatic mode; null hides the button.
  final VoidCallback? onCheckSource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = context.localeTag;
    final theme = Theme.of(context);
    final choice =
        ref.watch(sourceChoiceSettingProvider).value ?? SourceChoice.auto;
    final source = ref.watch(marketDataSourceProvider).value;
    final about = ref.watch(aboutInfoProvider).value ?? AboutInfo.defaults();
    final labels = {
      SourceChoice.auto: l10n.settingsSourceAuto,
      SourceChoice.binance: 'Binance',
      SourceChoice.binanceUs: 'Binance.US',
      SourceChoice.coingecko: 'CoinGecko',
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabSettings)),
      body: ListView(
        children: [
          _Section(l10n.settingsSource),
          RadioGroup<SourceChoice>(
            groupValue: choice,
            onChanged: (v) {
              if (v == null) return;
              unawaited(
                ref.read(sourceChoiceSettingProvider.notifier).choose(v),
              );
            },
            child: Column(
              children: [
                for (final c in SourceChoice.values)
                  RadioListTile<SourceChoice>(
                    key: Key('source_${c.storageValue}'),
                    value: c,
                    title: Text(labels[c]!),
                    subtitle: c == SourceChoice.auto
                        ? Text(l10n.settingsSourceHint)
                        : null,
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.travel_explore_outlined),
            title: Text(
              l10n.settingsCurrentSource(source?.attribution ?? '…'),
              key: const Key('current_source'),
            ),
            trailing: onCheckSource == null || choice != SourceChoice.auto
                ? null
                : TextButton(
                    key: const Key('check_source'),
                    onPressed: onCheckSource,
                    child: Text(l10n.settingsCheckSource),
                  ),
          ),
          const Divider(),
          _Section(l10n.about),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: Text(l10n.aboutDataSources),
            subtitle: Text(
              l10n.aboutTermsChecked(
                MoneyFormat.date(about.termsCheckedOn, locale: locale),
              ),
            ),
          ),
          for (final s in about.sources)
            ListTile(
              dense: true,
              leading: const SizedBox(width: 24),
              title: Text(s.name),
              subtitle: Text(s.attribution),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _open(s.termsUrl),
            ),
          ListTile(
            leading: const Icon(Icons.outbox_outlined),
            title: Text(l10n.aboutDataFlows),
            subtitle: Text(l10n.aboutDataFlowsText),
            isThreeLine: true,
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(l10n.privacyPolicy),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(about.privacyPolicyUrl),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: Text(l10n.termsOfUse),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(about.termsOfUseUrl),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(l10n.aboutInstallSource),
            subtitle: Text(about.installSource ?? l10n.aboutInstallSourceNone),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(
              l10n.version(about.version.isEmpty ? '…' : about.version),
            ),
            subtitle: Text(
              about.repositoryUrl.toString(),
              style: theme.textTheme.bodySmall,
            ),
            onTap: () => _open(about.repositoryUrl),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _open(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
