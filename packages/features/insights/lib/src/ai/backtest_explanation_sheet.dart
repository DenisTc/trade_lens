import 'dart:async';

import 'package:backtest/backtest.dart';
import 'package:features_insights/src/ai/backtest_explanation_controller.dart';
import 'package:features_insights/src/ai/summary_sheet_widgets.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showBacktestExplanationSheet(
  BuildContext context, {
  required BacktestMetrics metrics,
  VoidCallback? onOpenAiSettings,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => FractionallySizedBox(
    heightFactor: 0.86,
    child: BacktestExplanationSheet(
      metrics: metrics,
      onOpenAiSettings: onOpenAiSettings == null
          ? null
          : () {
              Navigator.of(sheetContext).pop();
              onOpenAiSettings();
            },
    ),
  ),
);

class BacktestExplanationSheet extends ConsumerStatefulWidget {
  const BacktestExplanationSheet({
    required this.metrics,
    this.onOpenAiSettings,
    super.key,
  });

  final BacktestMetrics metrics;
  final VoidCallback? onOpenAiSettings;

  @override
  ConsumerState<BacktestExplanationSheet> createState() =>
      _BacktestExplanationSheetState();
}

class _BacktestExplanationSheetState
    extends ConsumerState<BacktestExplanationSheet> {
  // Separate sheet openings own separate cancellation and billing lifetimes.
  final _key = UniqueKey();

  void _start({bool demo = false}) {
    final controller = ref.read(
      backtestExplanationControllerProvider(_key).notifier,
    );
    unawaited(
      demo
          ? controller.showExample(languageCode: context.localeTag)
          : controller.start(
              metrics: widget.metrics,
              languageCode: context.localeTag,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cloudReadiness = ref.watch(aiReadinessProvider);
    final onDeviceAvailable =
        ref.watch(onDeviceAvailabilityProvider).value ==
        OnDeviceAvailability.available;
    final readiness = onDeviceAvailable ? AiReadiness.ready : cloudReadiness;
    final state = ref.watch(backtestExplanationControllerProvider(_key));
    if (state.isIdle && readiness == AiReadiness.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final stillReady =
            ref.read(onDeviceAvailabilityProvider).value ==
                OnDeviceAvailability.available ||
            ref.read(aiReadinessProvider) == AiReadiness.ready;
        if (!mounted || !stillReady) {
          return;
        }
        if (ref.read(backtestExplanationControllerProvider(_key)).isIdle) {
          _start();
        }
      });
    }
    return AiSummarySheetFrame(
      title: context.l10n.backtestExplain,
      subtitle: widget.metrics.symbol,
      readiness: readiness,
      isIdle: state.isIdle,
      text: state.text,
      // Auto-start is pending until the post-frame callback runs. Do not
      // offer Retry before the first attempt has even started.
      running:
          state.running || (state.isIdle && readiness == AiReadiness.ready),
      demo: state.demo,
      onDevice: state.onDevice,
      usage: state.usage,
      costUsd: state.costUsd,
      error: state.error,
      onOpenAiSettings: widget.onOpenAiSettings,
      onDemo: () => _start(demo: true),
      onConsent: () => ref.read(aiConsentProvider.notifier).grant(),
      onStop: ref
          .read(backtestExplanationControllerProvider(_key).notifier)
          .stop,
      onRetry: () => _start(demo: state.demo),
    );
  }
}
