/// TradeLens · the pull-request reviewer that runs in CI.
///
/// One `git diff`, one Claude call with structured output, one comment on
/// the pull request. It reuses the app's own Claude client — the same
/// transport interface, the same model config and cost accounting — which
/// is the point: that package is pure Dart and works outside the app.
library;

export 'src/comment.dart';
export 'src/diff.dart';
export 'src/findings.dart';
export 'src/github.dart';
export 'src/http_transport.dart';
export 'src/response.dart';
export 'src/review.dart';
