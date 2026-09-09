import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'source_choice.g.dart';

/// What the user picked in Settings: automatic region resolution or one
/// source by id. Persisted in the settings store; the app's DI watches it
/// and rebuilds the live stack (spec: "Источник можно выбрать вручную").
enum SourceChoice {
  auto('auto'),
  binance('binance'),
  binanceUs('binance_us'),
  coingecko('coingecko');

  SourceChoice(this.storageValue);

  final String storageValue;

  static SourceChoice fromStorage(String? value) => SourceChoice.values
      .firstWhere((c) => c.storageValue == value, orElse: () => auto);
}

@Riverpod(keepAlive: true)
class SourceChoiceSetting extends _$SourceChoiceSetting {
  @override
  Stream<SourceChoice> build() => ref
      .watch(settingsStoreProvider)
      .watch(SettingsKeys.manualSource)
      .map(SourceChoice.fromStorage);

  Future<void> choose(SourceChoice choice) async {
    final store = ref.read(settingsStoreProvider);
    if (choice == SourceChoice.auto) {
      await store.delete(SettingsKeys.manualSource);
    } else {
      await store.write(SettingsKeys.manualSource, choice.storageValue);
    }
  }
}
