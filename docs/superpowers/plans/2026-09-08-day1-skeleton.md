# TradeLens · День 1: каркас репозитория Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Melos-монорепо с пустыми, но собирающимися пакетами по слоям, архитектурными тестами, работающим codegen и зелёным GitHub Actions, чтобы дни 2–8 добавляли только код функций.

**Architecture:** Pub workspaces + Melos 8 (конфиг в корневом `pubspec.yaml`). Пакеты по слоям из раздела «Архитектура и пакеты» спеки: `core`, `domain`, `data_market`, `data_local`, `ws_client`, `chart`, `sdui`, `ai_insights`, `features/*`, `apps/mobile`. Направление зависимостей защищено тестом в `tooling/arch_test`, который читает pubspec-ы и сканирует импорты.

**Tech Stack:** Flutter 3.47.2 stable через fvm, Dart 3.12, Melos 8.6, very_good_analysis 11, Riverpod 3.4 + riverpod_generator 4, go_router 18, build_runner 2.16, GitHub Actions.

**Spec:** `docs/spec/tradelens-prd-tid-v1.2.md` (разделы «Архитектура и пакеты», «Riverpod: правила», «Тесты» → Architecture, «CI/CD», «План по дням» → День 1).

## Global Constraints

- Flutter: «Стабильный канал на дату старта, через fvm. Версию зафиксировать в `.fvmrc` и в CI» → `3.47.2`.
- State: «Riverpod 3.x, только codegen: `@riverpod`», DI только через провайдеры, без GetIt.
- Деньги: «Decimal (пакет `decimal`) … запрет double в domain».
- Архитектурный тест: «Направление зависимостей пакетов, запрет double в domain, запрет прямых импортов Dio из feature» — минимум 3 теста.
- CI: «melos bootstrap → build_runner build → analyze → test с coverage → build apk --debug», артефакт APK и отчёт покрытия, отдельный golden-job, отдельный e2e-job на macOS с patrol.
- «Никаких секретов в репозитории … Пример файла env.example.json в репозитории».
- Коммиты от имени владельца репозитория, без Co-Authored-By.
- Каждый день заканчивается зелёным CI и коммитом в main.

---

### Task 1: Toolchain и корень монорепо

**Files:**
- Create: `.fvmrc`, `.gitignore`, `pubspec.yaml`, `analysis_options.yaml`, `.editorconfig`, `env.example.json`

**Produces:** корневой workspace, в который Task 2–4 добавляют пакеты в список `workspace:`.

- [ ] **Step 1: `.fvmrc`**

```json
{
  "flutter": "3.47.2"
}
```

- [ ] **Step 2: корневой `pubspec.yaml`**

```yaml
name: tradelens_workspace
publish_to: none
environment:
  sdk: ^3.12.0
workspace:
  - packages/core
  - packages/domain
  - packages/data_market
  - packages/data_local
  - packages/ws_client
  - packages/chart
  - packages/sdui
  - packages/ai_insights
  - packages/features/markets
  - packages/features/portfolio
  - packages/features/insights
  - packages/features/settings
  - apps/mobile
  - tooling/arch_test
dev_dependencies:
  melos: ^8.6.0
melos:
  scripts:
    generate:
      run: melos exec -c 1 --depends-on build_runner -- dart run build_runner build --delete-conflicting-outputs
    analyze:
      run: melos exec -- dart analyze --fatal-infos .
    test:
      run: melos exec --dir-exists test -- flutter test --coverage
    format:
      run: dart format --set-exit-if-changed .
```

- [ ] **Step 3: `analysis_options.yaml`**

```yaml
include: package:very_good_analysis/analysis_options.yaml
analyzer:
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "**/*.drift.dart"
linter:
  rules:
    public_member_api_docs: false
    lines_longer_than_80_chars: false
```

`very_good_analysis` подключается в каждом пакете как dev_dependency, а корневой файл только `include`-ится из пакетов через `include: ../../analysis_options.yaml`.

- [ ] **Step 4: `.gitignore`, `.editorconfig`, `env.example.json`**

`env.example.json`:
```json
{
  "COINGECKO_DEMO_KEY": "",
  "ONESIGNAL_APP_ID": "",
  "APPSFLYER_DEV_KEY": "",
  "APPSFLYER_IOS_APP_ID": "",
  "SENTRY_DSN": ""
}
```
`.gitignore` включает `env.json`, `.fvm/`, `build/`, `.dart_tool/`, `coverage/`, `pubspec_overrides.yaml`, `*.g.dart` не игнорируем (генерация в CI, но коммитим сгенерированное? Решение: **не коммитим**, CI генерирует; игнорируем `**/*.g.dart`, `**/*.freezed.dart`, `**/*.drift.dart`).

- [ ] **Step 5: Commit** `chore: bootstrap melos workspace`

---

### Task 2: Пакет `core` с `Result`

**Files:**
- Create: `packages/core/pubspec.yaml`, `packages/core/lib/core.dart`, `packages/core/lib/src/result.dart`, `packages/core/test/result_test.dart`

**Produces:** `sealed class Result<T, E>` с `Ok<T,E>(value)`, `Err<T,E>(error)`, методами `map`, `when`, `isOk`, `isErr`. Re-export `package:decimal/decimal.dart`.

- [ ] **Step 1: failing test**

```dart
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('Ok maps value and keeps error type', () {
    const Result<int, String> r = Ok(2);
    expect(r.map((v) => v * 2), const Ok<int, String>(4));
  });
  test('Err does not map', () {
    const Result<int, String> r = Err('boom');
    expect(r.map((v) => v * 2), const Err<int, String>('boom'));
  });
  test('when dispatches', () {
    const Result<int, String> r = Ok(1);
    expect(r.when(ok: (v) => 'ok $v', err: (e) => 'err $e'), 'ok 1');
  });
}
```

- [ ] **Step 2: run, expect FAIL** `cd packages/core && fvm dart test`
- [ ] **Step 3: implement** `Result` как sealed class с `const` конструкторами и `==`/`hashCode`.
- [ ] **Step 4: run, expect PASS**
- [ ] **Step 5: Commit** `feat(core): add Result type`

---

### Task 3: Остальные пакеты-заглушки

**Files:**
- Create для каждого из `domain`, `data_market`, `data_local`, `ws_client`, `chart`, `sdui`, `ai_insights`, `features/markets`, `features/portfolio`, `features/insights`, `features/settings`: `pubspec.yaml`, `lib/<name>.dart` с одним библиотечным doc-комментарием и одним экспортом, `test/<name>_test.dart` с smoke-тестом.

Зависимости строго по слоям (это же проверяет Task 5):

| Пакет | Разрешённые внутренние deps |
|---|---|
| core | — |
| domain | core |
| ws_client | core |
| data_market | core, domain, ws_client |
| data_local | core, domain |
| chart | core |
| sdui | core |
| ai_insights | core, domain |
| features/* | core, domain, data_market, data_local, ws_client, chart, sdui, ai_insights |
| apps/mobile | всё |

Flutter-пакеты (с `flutter:` sdk): chart, sdui, features/*, data_local (drift + flutter), остальные чистый Dart.

- [ ] **Step 1:** создать пакеты, `fvm flutter pub get` в корне, `melos list` показывает 14 пакетов.
- [ ] **Step 2:** `melos run test` зелёный.
- [ ] **Step 3: Commit** `chore: add layered package skeleton`

---

### Task 4: `apps/mobile` с Riverpod codegen и go_router

**Files:**
- Create: `apps/mobile/` через `fvm flutter create --org com.denistc --project-name tradelens --platforms ios,android`
- Create: `apps/mobile/lib/app.dart`, `apps/mobile/lib/router.dart`, `apps/mobile/lib/providers/app_info.dart` (`@Riverpod(keepAlive: true) String appName(Ref ref) => 'TradeLens';`)
- Test: `apps/mobile/test/app_test.dart` — pumpWidget с `ProviderScope`, ожидаем текст `TradeLens` и что маршрут `/p/BTCUSDT` рендерит заглушку экрана пары с символом.

- [ ] **Step 1: failing widget test**
- [ ] **Step 2:** `melos run generate`, тест падает на отсутствии виджетов
- [ ] **Step 3:** реализовать `TradeLensApp` (MaterialApp.router, тема Material 3, `ThemeMode.system`), маршруты `/` (MarketsPlaceholder) и `/p/:symbol` (PairPlaceholder).
- [ ] **Step 4:** тест зелёный, `fvm flutter build apk --debug` проходит локально.
- [ ] **Step 5: Commit** `feat(app): bootstrap TradeLens app with riverpod and go_router`

---

### Task 5: Архитектурные тесты `tooling/arch_test`

**Files:**
- Create: `tooling/arch_test/pubspec.yaml`, `tooling/arch_test/lib/arch_test.dart` (чтение pubspec-ов, список dart-файлов), `tooling/arch_test/test/dependency_direction_test.dart`, `test/no_double_in_domain_test.dart`, `test/no_dio_in_features_test.dart`

**Produces:** `Map<String, Set<String>> internalDependencies(Directory root)`, `Iterable<File> dartFilesUnder(Directory lib)`.

- [ ] **Step 1: три failing теста**

```dart
// dependency_direction_test.dart
test('packages depend only on allowed layers', () {
  final deps = internalDependencies(repoRoot);
  for (final entry in deps.entries) {
    final allowed = allowedDependencies[entry.key]!;
    expect(entry.value.difference(allowed), isEmpty,
        reason: '${entry.key} depends on forbidden packages');
  }
});
// no_double_in_domain_test.dart
test('domain does not use double', () {
  for (final f in dartFilesUnder(Directory('$repoRoot/packages/domain/lib'))) {
    expect(RegExp(r'\bdouble\b').hasMatch(f.readAsStringSync()), isFalse,
        reason: '${f.path} uses double');
  }
});
// no_dio_in_features_test.dart
test('features do not import dio', () { ... RegExp(r"import\s+'package:dio/") ... });
```

Чтобы тесты были нетривиальны, в Step 2 намеренно добавить `double` в domain и увидеть красный тест, затем убрать.

- [ ] **Step 2–4:** реализация, красный → зелёный.
- [ ] **Step 5: Commit** `test(arch): guard dependency direction, no double in domain, no dio in features`

---

### Task 6: GitHub Actions, README, ADR

**Files:**
- Create: `.github/workflows/ci.yml`, `README.md`, `docs/decisions/0001-monorepo-layout.md`, `docs/decisions/backlog.md`, `LICENSE` (MIT)

`ci.yml`: jobs `build` (ubuntu: checkout → subosito/flutter-action с версией из `.fvmrc` → cache pub → `dart pub global activate melos` → `melos bootstrap` → `melos run generate` → `melos run analyze` → `melos run format` → `melos run test` → `flutter build apk --debug` в `apps/mobile` → upload APK + coverage), `golden` (ubuntu, `flutter test --tags golden`, upload `**/failures/**` при падении), `e2e` (macos, только `main` или label `e2e`, ставит `patrol_cli` и печатает «no scenarios yet» — заглушка по спеке дня 1).

- [ ] **Step 1:** написать workflow, проверить `actionlint`/yaml-парсинг локально.
- [ ] **Step 2:** README: название, бейдж CI, схема пакетов из спеки, раздел «Статус» с чеклистом дней, «Решения» со ссылками на ADR.
- [ ] **Step 3: Commit** `ci: add analyze/test/build workflow, README and ADR-0001`

---

### Task 7: Codex-ревью и хвосты

- [ ] `codex exec` ревью диффа Дня 1 по чеклисту: направление зависимостей, лишние зависимости, CI, секреты.
- [ ] Исправить находки, финальный `melos run analyze && melos run test`, коммит.

## Вне автоматизации (руками владельца)

- Bundle id и проверка имени «TradeLens» в App Store / Google Play.
- App Store Connect, fastlane match, первый ручной upload в TestFlight.
- Firebase-проект, AppsFlyer Zero аккаунт, OneSignal, Sentry DSN → `env.json`.
- `git push` в `github.com/DenisTc/trade_lens` и секреты GitHub Actions.
