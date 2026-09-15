import 'dart:async';

import 'package:ai_insights/ai_insights.dart';
import 'package:domain/domain.dart';
import 'package:features_insights/src/ai/move_summary_controller.dart';
import 'package:features_insights/src/ai/summary_sheet_widgets.dart';
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

    return AiSummarySheetFrame(
      title: l10n.aiSummaryTitle,
      subtitle: widget.instrument.displayName,
      readiness: readiness,
      isIdle: state.isIdle,
      text: state.text,
      running: state.running,
      demo: state.demo,
      usage: state.usage,
      costUsd: state.costUsd,
      error: state.error,
      onOpenAiSettings: widget.onOpenAiSettings,
      onDemo: () => _start(demo: true),
      onConsent: () => ref.read(aiConsentProvider.notifier).grant(),
      onStop: ref
          .read(moveSummaryControllerProvider(widget.instrument).notifier)
          .cancel,
      onRetry: () => _retry(demo: state.demo),
      beforeProse: [
        if (state.toolCalls.isNotEmpty) _ToolChips(calls: state.toolCalls),
      ],
      afterProse: [
        if (state.structure case final structure?) ...[
          const SizedBox(height: 20),
          _StructureBlock(structure: structure),
        ],
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
