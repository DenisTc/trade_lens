/// TradeLens · Claude API client for the "move summary": SSE streaming,
/// a tool loop over data the app already holds (`get_klines`,
/// `get_orderbook`), a second call with structured output, usage and cost
/// accounting. Pure Dart: the transport (Dio + pinning) and the widgets
/// live elsewhere.
library;

export 'src/errors.dart';
export 'src/model_config.dart';
export 'src/move_structure.dart';
export 'src/sse.dart';
export 'src/stream_events.dart';
export 'src/summary_session.dart';
export 'src/tools.dart';
export 'src/transport.dart';
