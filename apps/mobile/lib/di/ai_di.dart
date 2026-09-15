import 'package:core/core.dart';
import 'package:data_local/data_local.dart';
import 'package:data_market/data_market.dart';
import 'package:features_insights/features_insights.dart';
import 'package:features_shared/features_shared.dart';
import 'package:on_device_llm/on_device_llm.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

/// Screenshots and demos without a key or a network. The flag replaces only
/// the cloud transport; an available on-device runtime stays local-first.
const aiDemoMode = bool.fromEnvironment('TL_AI_DEMO');

/// Binds the AI summary to the real device: the key in the keychain, the
/// pinned Dio transport to api.anthropic.com.
List<Override> aiOverrides() => [
  secretStoreProvider.overrideWithValue(SecureSecretStore()),
  onDeviceLlmProvider.overrideWithValue(OnDeviceLlm()),
  claudeTransportProvider.overrideWith(
    (ref) => aiDemoMode
        ? DemoClaudeTransport()
        : DioClaudeTransport(logger: const PrintLogger()),
  ),
];
