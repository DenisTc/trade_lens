import 'dart:async';

import 'package:ai_insights/ai_insights.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';

/// Shared layout and controls for streaming AI answers.
class AiSummarySheetFrame extends StatelessWidget {
  const AiSummarySheetFrame({
    required this.title,
    required this.subtitle,
    required this.readiness,
    required this.isIdle,
    required this.text,
    required this.running,
    required this.demo,
    required this.usage,
    required this.costUsd,
    required this.onDemo,
    required this.onConsent,
    required this.onStop,
    required this.onRetry,
    this.error,
    this.onDevice = false,
    this.onOpenAiSettings,
    this.beforeProse = const [],
    this.afterProse = const [],
    super.key,
  });

  final String title;
  final String subtitle;
  final AiReadiness readiness;
  final bool isIdle;
  final String text;
  final bool running;
  final bool demo;
  final bool onDevice;
  final Usage usage;
  final double costUsd;
  final AiError? error;
  final VoidCallback onDemo;
  final Future<void> Function() onConsent;
  final VoidCallback onStop;
  final VoidCallback onRetry;
  final VoidCallback? onOpenAiSettings;
  final List<Widget> beforeProse;
  final List<Widget> afterProse;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
                if (demo)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _Badge(
                      key: const Key('ai_demo_badge'),
                      text: l10n.aiExampleBadge,
                    ),
                  ),
                if (onDevice)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _Badge(
                      key: const Key('ai_on_device_badge'),
                      text: l10n.aiOnDeviceBadge,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(subtitle, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              children: [
                if (isIdle && readiness != AiReadiness.ready)
                  _Gate(
                    readiness: readiness,
                    onDemo: onDemo,
                    onConsent: onConsent,
                    onOpenAiSettings: onOpenAiSettings,
                  )
                else ...[
                  ...beforeProse,
                  if (text.isEmpty && running)
                    const _ProseSkeleton()
                  else
                    SelectableText(
                      text,
                      key: const Key('ai_summary_text'),
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                    ),
                  ...afterProse,
                  if (error case final error?) ...[
                    const SizedBox(height: 16),
                    _ErrorNote(error: error),
                  ],
                  const SizedBox(height: 20),
                  Text(l10n.aiDisclaimer, style: theme.textTheme.bodySmall),
                  if (onDevice)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        l10n.aiOnDeviceCost,
                        key: const Key('ai_on_device_cost'),
                        style: TradeLensText.mono(
                          size: 11,
                          weight: FontWeight.w400,
                          color: t.muted,
                        ),
                      ),
                    )
                  else if (usage.total > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        l10n.aiCost(costUsd.toStringAsFixed(4), usage.total),
                        key: const Key('ai_cost'),
                        style: TradeLensText.mono(
                          size: 11,
                          weight: FontWeight.w400,
                          color: t.muted,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (!isIdle || readiness == AiReadiness.ready)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: running
                  ? OutlinedButton(
                      key: const Key('ai_stop'),
                      onPressed: onStop,
                      child: Text(l10n.aiStop),
                    )
                  : FilledButton(
                      key: const Key('ai_retry'),
                      onPressed: onRetry,
                      child: Text(l10n.aiRetry),
                    ),
            ),
        ],
      ),
    );
  }
}

/// Why the summary cannot run yet, and the way out of it.
class _Gate extends StatelessWidget {
  const _Gate({
    required this.readiness,
    required this.onDemo,
    required this.onConsent,
    this.onOpenAiSettings,
  });

  final AiReadiness readiness;
  final VoidCallback onDemo;
  final Future<void> Function() onConsent;
  final VoidCallback? onOpenAiSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final (title, body) = switch (readiness) {
      AiReadiness.disabled => (l10n.aiDisabledTitle, l10n.aiDisabledBody),
      AiReadiness.noKey => (l10n.aiNoKeyTitle, l10n.aiNoKeyBody),
      AiReadiness.noConsent => (l10n.aiConsentTitle, l10n.aiConsentBody),
      AiReadiness.ready => ('', ''),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(body, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
        const SizedBox(height: 20),
        if (readiness == AiReadiness.noConsent)
          FilledButton(
            key: const Key('ai_consent_agree'),
            onPressed: () => unawaited(onConsent()),
            child: Text(l10n.aiConsentAgree),
          )
        else if (readiness == AiReadiness.noKey && onOpenAiSettings != null)
          FilledButton(
            key: const Key('ai_open_settings'),
            onPressed: onOpenAiSettings,
            child: Text(l10n.aiOpenSettings),
          ),
        const SizedBox(height: 10),
        OutlinedButton(
          key: const Key('ai_show_example'),
          onPressed: onDemo,
          child: Text(l10n.aiShowExample),
        ),
      ],
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.error});

  final AiError error;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final t = context.tokens;
    final text = switch (error) {
      AiUnauthorized() => l10n.aiErrorUnauthorized,
      AiRateLimited() => l10n.aiErrorRateLimited,
      AiNetwork() => l10n.aiErrorNetwork,
      AiOnDevice(:final reason) => l10n.aiErrorOnDevice(reason),
      AiRefused() => l10n.aiErrorRefused,
      AiBudgetExceeded() => l10n.aiErrorBudget,
      AiBadRequest() ||
      AiInvalidResponse() ||
      AiCancelled() => l10n.aiErrorOther,
    };
    return Container(
      key: const Key('ai_error'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.downBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: t.down),
      ),
    );
  }
}

class _ProseSkeleton extends StatelessWidget {
  const _ProseSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Skeleton(),
      SizedBox(height: 10),
      Skeleton(),
      SizedBox(height: 10),
      Skeleton(width: 220),
    ],
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.accentBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: t.accentInk),
      ),
    );
  }
}
