/// TradeLens · WebSocket layer: one connection per source, subscription
/// registry with reference counting, command batching, outbound rate
/// limiting, reconnect with backoff, half-open detection by silence.
library;

export 'src/backoff.dart';
export 'src/coalesce.dart';
export 'src/outbound_limiter.dart';
export 'src/subscription_registry.dart';
export 'src/transport.dart';
export 'src/ws_client.dart';
