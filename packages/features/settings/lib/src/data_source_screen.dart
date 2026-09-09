import 'dart:async';

import 'package:features_settings/src/source_choice.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Manual data-source choice and the "check now" action.
class DataSourceScreen extends ConsumerWidget {
  const DataSourceScreen({super.key, this.onCheckSource});

  /// "Check source now" for the automatic mode; null hides the button.
  final VoidCallback? onCheckSource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final choice =
        ref.watch(sourceChoiceSettingProvider).value ?? SourceChoice.auto;
    final source = ref.watch(marketDataSourceProvider).value;
    final labels = {
      SourceChoice.auto: l10n.settingsSourceAuto,
      SourceChoice.binance: 'Binance',
      SourceChoice.binanceUs: 'Binance.US',
      SourceChoice.coingecko: 'CoinGecko',
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsSource)),
      body: ListView(
        children: [
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
          const Divider(),
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
        ],
      ),
    );
  }
}
