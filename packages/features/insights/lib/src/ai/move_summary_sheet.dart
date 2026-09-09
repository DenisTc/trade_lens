import 'dart:async';

import 'package:ai_insights/ai_insights.dart';
import 'package:domain/domain.dart';
import 'package:features_insights/src/ai/move_summary_controller.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart' hide Interval;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the move summary for [instrument]. On the root navigator so it
/// covers the floating tab bar, like the position editor.
Future<void> showMoveSummarySheet(
  BuildContext context, {
  required Instrument instrument,
  VoidCallback? onOpenAiSettings,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => FractionallySizedBox(
    heightFactor: 0.86,
    child: MoveSummarySheet(
      instrument: instrument,
      onOpenAiSettings: onOpenAiSettings == null
          ? null
          : () {
              Navigator.of(sheetContext).pop();
              onOpenAiSettings();
            },
    ),
  ),
);

/// Consent gate, then the streaming summary: prose, the tool calls the
/// model made, the structured block, what it cost, the disclaimer.
class MoveSummarySheet extends ConsumerStatefulWidget {
  const MoveSummarySheet({
    required this.instrument,
    super.key,
    this.onOpenAiSettings,
  });

  final Instrument instrument;
  final VoidCallback? onOpenAiSettings;

  @override
  ConsumerState<MoveSummarySheet> createState() => _MoveSummarySheetState();
}

class _MoveSummarySheetState extends ConsumerState<MoveSummarySheet> {
  var _started = false;

  void _start({bool demo = false}) {
    if (_started) return;
    _started = true;
    unawaited(
      ref
          .read(moveSummaryControllerProvider(widget.instrument).notifier)
          .start(demo: demo, languageCode: context.localeTag),
    );
  }

  void _retry({bool demo = false}) {
    _started = true;
    unawaited(
      ref
          .read(moveSummaryControllerProvider(widget.instrument).notifier)
          .retry(demo: demo, languageCode: context.localeTag),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final t = context.tokens;
    final theme = Theme.of(context);
    final readiness = ref.watch(aiReadinessProvider);
    final state = ref.watch(moveSummaryControllerProvider(widget.instrument));

    // Back at the gate (consent revoked, flag off, no key): the example
    // and consent buttons must work again.
    if (readiness != AiReadiness.ready && state.isIdle) _started = false;

    // Ready and untouched: start as soon as the sheet is on screen.
    if (readiness == AiReadiness.ready && state.isIdle && !_started) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Consent or the flag may have gone in the meantime.
        if (ref.read(aiReadinessProvider) == AiReadiness.ready) _start();
      });
    }

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
                Expanded(
                  child: Text(
                    l10n.aiSummaryTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (state.demo)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _Badge(
                      key: const Key('ai_demo_badge'),
                      text: l10n.aiExampleBadge,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              widget.instrument.displayName,
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              children: [
                if (state.isIdle && readiness != AiReadiness.ready)
                  _Gate(
                    readiness: readiness,
                    onOpenAiSettings: widget.onOpenAiSettings,
                    onDemo: () => _start(demo: true),
                    onConsent: () =>
                        ref.read(aiConsentProvider.notifier).grant(),
                  )
                else ...[
                  if (state.toolCalls.isNotEmpty)
                    _ToolChips(calls: state.toolCalls),
                  if (state.text.isEmpty && state.running)
                    const _ProseSkeleton()
                  else
                    SelectableText(
                      state.text,
                      key: const Key('ai_summary_text'),
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                    ),
                  if (state.structure case final structure?) ...[
                    const SizedBox(height: 20),
                    _StructureBlock(structure: structure),
                  ],
                  if (state.error case final error?) ...[
                    const SizedBox(height: 16),
                    _ErrorNote(error: error),
                  ],
                  const SizedBox(height: 20),
                  Text(l10n.aiDisclaimer, style: theme.textTheme.bodySmall),
                  if (state.usage.total > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        l10n.aiCost(
                          state.costUsd.toStringAsFixed(4),
                          state.usage.total,
                        ),
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
          if (!state.isIdle || readiness == AiReadiness.ready)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: state.running
                  ? OutlinedButton(
                      key: const Key('ai_stop'),
                      onPressed: ref
                          .read(
                            moveSummaryControllerProvider(widget.instrument)
                                .notifier,
                          )
                          .cancel,
                      child: Text(l10n.aiStop),
                    )
                  : FilledButton(
                      key: const Key('ai_retry'),
                      onPressed: () => _retry(demo: state.demo),
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

/// What the model asked for, in the order it asked.
class _ToolChips extends StatelessWidget {
  const _ToolChips({required this.calls});

  final List<ToolCall> calls;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final call in calls)
            Container(
              key: Key('ai_tool_${call.name}'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: t.raised,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                call.name == ToolSchemas.getKlines
                    ? l10n.aiToolKlines('${call.input['interval'] ?? ''}')
                    : l10n.aiToolBook,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// The structured output under the prose.
class _StructureBlock extends StatelessWidget {
  const _StructureBlock({required this.structure});

  final MoveStructure structure;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final t = context.tokens;
    final theme = Theme.of(context);
    final trendColor = switch (structure.trend) {
      Trend.up => t.up,
      Trend.down => t.down,
      Trend.sideways => t.muted,
    };
    Widget row(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(child: value),
        ],
      ),
    );
    return Container(
      key: const Key('ai_structure'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row(
            l10n.aiTrend,
            Text(switch (structure.trend) {
              Trend.up => l10n.aiTrendUp,
              Trend.down => l10n.aiTrendDown,
              Trend.sideways => l10n.aiTrendSideways,
            }, style: theme.textTheme.titleSmall?.copyWith(color: trendColor)),
          ),
          row(
            l10n.aiVolatility,
            Text(switch (structure.volatility) {
              Volatility.low => l10n.aiVolLow,
              Volatility.medium => l10n.aiVolMedium,
              Volatility.high => l10n.aiVolHigh,
            }, style: theme.textTheme.titleSmall),
          ),
          if (structure.keyLevels.isNotEmpty)
            row(
              l10n.aiKeyLevels,
              Text(
                structure.keyLevels.join('  ·  '),
                style: TradeLensText.mono(size: 13, color: t.text),
              ),
            ),
          row(
            l10n.aiDataLabel,
            Text(
              l10n.aiDataFrom(
                structure.dataSource,
                MoneyFormat.time(structure.dataAsOf, locale: context.localeTag),
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
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
