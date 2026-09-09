import 'package:features_settings/src/about_info.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sources with links to their terms, the date the terms were last
/// checked, what leaves the device, privacy policy, terms of use, install
/// source, version.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = context.localeTag;
    final theme = Theme.of(context);
    final about = ref.watch(aboutInfoProvider).value ?? AboutInfo.defaults();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.about)),
      body: ListView(
        children: [
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
          const Divider(),
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
          const Divider(),
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
