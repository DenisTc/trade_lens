import 'package:ai_insights/src/stream_events.dart';
import 'package:ai_insights/src/summary_session.dart';
import 'package:ai_insights/src/transport.dart';

/// A summary of already computed metrics, independent of its runtime.
abstract interface class SummaryProvider {
  Stream<SummaryEvent> explainMetrics({
    required Map<String, Object?> metrics,
    required String apiKey,
    required String languageCode,
    required CancelSignal cancel,
  });

  Usage get usage;
  double get costUsd;
}
