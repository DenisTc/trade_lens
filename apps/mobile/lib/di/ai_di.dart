import 'package:core/core.dart';
import 'package:data_local/data_local.dart';
import 'package:data_market/data_market.dart';
import 'package:features_insights/features_insights.dart';
import 'package:features_shared/features_shared.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

/// Screenshots and demos without a key or a network:
/// `--dart-define=TL_AI_DEMO=true` makes every summary replay the bundled
/// example. Off in normal builds.
const aiDemoMode = bool.fromEnvironment('TL_AI_DEMO');

/// Binds the AI summary to the real device: the key in the keychain, the
/// pinned Dio transport to api.anthropic.com.
List<Override> aiOverrides() => [
  secretStoreProvider.overrideWithValue(SecureSecretStore()),
  claudeTransportProvider.overrideWith(
    (ref) => aiDemoMode
        ? DemoClaudeTransport()
        : DioClaudeTransport(logger: const PrintLogger()),
  ),
];
