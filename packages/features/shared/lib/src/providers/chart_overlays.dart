import 'package:domain/domain.dart';
import 'package:features_shared/src/providers/storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chart_overlays.g.dart';

/// Whether the pair chart draws its moving averages. One switch for both
/// lines: a trader who wants them wants the pair, and the periods (7 and
/// 25) are the ones every exchange app defaults to. Off until turned on,
/// remembered across launches.
@Riverpod(keepAlive: true)
class ChartOverlaysSetting extends _$ChartOverlaysSetting {
  @override
  Stream<bool> build() => ref
      .watch(settingsStoreProvider)
      .watch(SettingsKeys.chartOverlays)
      .map((v) => v == 'true');

  Future<void> toggle() async {
    final store = ref.read(settingsStoreProvider);
    if (state.value ?? false) {
      await store.delete(SettingsKeys.chartOverlays);
    } else {
      await store.write(SettingsKeys.chartOverlays, 'true');
    }
  }
}
