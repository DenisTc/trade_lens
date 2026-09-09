# Дизайн «Оптика» во Flutter

Спец: `docs/design/brief.md`, холст https://claude.ai/code/artifact/2c0b0281-a255-499b-a2ff-3c5a4182e8bf

- [x] 1. Шрифты Onest + IBM Plex Mono в `features_shared/assets/fonts`, токены двух тем в `tokens.dart`, `buildTradeLensTheme` (ColorScheme вручную, textTheme, компонентные темы), `TradeLensText.mono`
- [x] 2. Общие виджеты: `LensRing`, `ChangeChip`, `StatusChip` (кольцо + подпись), `ScreenTitle`, `SectionHeader`; `Skeleton` на токене raised
- [x] 3. Тема: `AppThemeSetting` (SettingsKeys.uiTheme), `themeMode` в `MaterialApp`, экран «Оформление» с мини-превью, маршрут `/settings/appearance`, строки l10n
- [x] 4. `HomeShell`: плавающее стеклянное меню (`GlassTabBar`, `extendBody`), бейдж источника переезжает в футер списков
- [x] 5. Рынки: шапка с вордмарком, статусом и раскрывающимся поиском; подзаголовок; строки 64 px; скелетоны
- [x] 6. Пара: заголовок с подписью, цена 34 mono + чип, пилюли интервалов с кольцом, тема графика из токенов, стакан и лента в моно
- [x] 7. Портфель: итог с чипом PnL, статус кольцом, строки 72 px, кнопка «Добавить позицию» вместо FAB
- [x] 8. Настройки: хаб с иконками в квадратах, «О приложении» с версией по центру, язык и источник в том же стиле
- [x] 9. Иконка приложения (flutter_launcher_icons, adaptive для Android)
- [x] 10. Тесты и golden-эталоны обновлены, `melos analyze/test/test:golden` зелёные, Codex-ревью, README-скриншоты, релиз в `main` с тегом
