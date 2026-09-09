import 'dart:async';

import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The user's own Claude API key and the consent to send this pair's
/// candles and order book with it. The key is stored in the device
/// keychain and shown masked; the field starts empty on every visit so a
/// stored key is never rendered back to screen or into a screenshot.
class AiKeyScreen extends ConsumerStatefulWidget {
  const AiKeyScreen({super.key, this.onOpenPrivacyPolicy});

  final VoidCallback? onOpenPrivacyPolicy;

  @override
  ConsumerState<AiKeyScreen> createState() => _AiKeyScreenState();
}

class _AiKeyScreenState extends ConsumerState<AiKeyScreen> {
  final _controller = TextEditingController();
  var _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    setState(() => _saving = true);
    await ref.read(aiApiKeyProvider.notifier).save(value);
    if (!mounted) return;
    _controller.clear();
    setState(() => _saving = false);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final t = context.tokens;
    final theme = Theme.of(context);
    final key = ref.watch(aiApiKeyProvider).value;
    final consent = ref.watch(aiConsentProvider).value ?? false;
    final enabled = ref.watch(aiInsightsEnabledProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiSettingsRow)),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: [
          if (!enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                l10n.aiDisabledBody,
                key: const Key('ai_disabled_note'),
                style: theme.textTheme.bodySmall?.copyWith(color: t.warn),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              l10n.aiKeyStored,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              key: const Key('ai_key_field'),
              controller: _controller,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l10n.aiKeyTitle,
                hintText: 'sk-ant-…',
              ),
              onSubmitted: (_) => unawaited(_save()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: FilledButton(
              key: const Key('ai_key_save'),
              onPressed: _saving ? null : () => unawaited(_save()),
              child: Text(l10n.save),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    key == null || key.isEmpty
                        ? l10n.aiKeyNone
                        : l10n.aiKeySet(_mask(key)),
                    key: const Key('ai_key_status'),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (key != null && key.isNotEmpty)
                  TextButton(
                    key: const Key('ai_key_clear'),
                    onPressed: () =>
                        unawaited(ref.read(aiApiKeyProvider.notifier).clear()),
                    child: Text(l10n.aiKeyClear),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: t.line),
          SettingsRow(
            title: l10n.aiConsentTitle,
            subtitle: consent ? l10n.aiConsentGiven : l10n.aiConsentNone,
            trailing: Switch(
              key: const Key('ai_consent_switch'),
              value: consent,
              onChanged: (value) => unawaited(
                value
                    ? ref.read(aiConsentProvider.notifier).grant()
                    : ref.read(aiConsentProvider.notifier).revoke(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              l10n.aiConsentBody,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ),
          if (widget.onOpenPrivacyPolicy != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: widget.onOpenPrivacyPolicy,
                  child: Text(l10n.privacyPolicy),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// `sk-ant-…f3a9`: enough to tell two keys apart, not enough to use one.
  static String _mask(String key) => key.length <= 8
      ? '…'
      : '${key.substring(0, 7)}…${key.substring(key.length - 4)}';
}
