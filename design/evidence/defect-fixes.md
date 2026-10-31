# AS-83: две правки после функционального browser QA

31.10.2026. Роль: автор прототипа, targeted regression. Это не повторная независимая
G4/G5 и не функциональная проверка Android-приложения.

Исходное независимое evidence: `.local/android/execution/design-browser-qa/evidence.json`
и screenshot `navigation-font200-360.png`. Они относятся к прежним source SHA.
QA script, его evidence и остальные backend/PG/production-файлы не изменялись.

## Изменение поведения

1. `preview/review.js`, только ветка `notification-optin`: once close-listener
   повторно рисует D07 из модели после отмены, возвращает фокус к checkbox и
   сообщает, что уведомления не включены. Отмена кнопкой и Escape оставляют
   checkbox unchecked; явное подтверждение по-прежнему включает его. Native
   промежуточное checked-состояние клика не выдаётся за подтверждённый opt-in.
2. `preview/layout.css`, только `.tabs` и `.tabs button`: включён flex wrap,
   intrinsic basis `auto`, normal white-space и overflow-wrap fallback. Если
   обе подписи не помещаются, каждая получает отдельную строку и полный target.
   `preview/review.css` восстановлен генератором. Font scale не уменьшается.

`sources/browser_regressions.py` проверяет реальный DOM в Chromium, без mock DOM
и без сетевого backend. Он отдельно сохраняет наблюдаемый RED и GREEN:

- [RED](browser-regressions-red.json): оба исходных дефекта воспроизведены до
  изменения preview. Checkbox остался checked после cancel; glyph bounds
  «Сегодня» 48..201 и «Диалог» 191..326 вышли за targets и пересеклись.
- [GREEN](browser-regressions-green.json): оба теста проходят. Cancel + Escape,
  сохранение unchecked после ухода/возврата и positive confirm path проверены.
  12 layout cases: ширины 360/412/480 × 100/200% × light/dark; подписи внутри
  реальных targets, без пересечения, каждый target ≥48 px, переходы кликабельны.
  В 360/200% фактический font size — 32 px, targets 41..319 на разных строках;
  glyph bounds «Сегодня» 103.5..256.5 и «Диалог» 112.5..247.5.
- [Исправленная навигация при 200%](navigation-green-200-360.png) осмотрена автором.
  Runtime page errors и внешних запросов нет. Source hashes preview неизменны
  во время каждого прогона; RED/GREEN намеренно привязаны к разным версиям.

## Команды

Из workspace `/home/codex/assistant`:

```bash
source .local/android/execution/qa-env.sh
.local/android/qa/venv/bin/python .local/android/execution/design/sources/browser_regressions.py --phase red
python3 .local/android/execution/design/sources/build.py
.local/android/qa/venv/bin/python .local/android/execution/design/sources/browser_regressions.py --phase green
python3 .local/android/execution/design/sources/build.py --check
python3 .local/android/execution/design/sources/verify.py
```

RED завершился exit 1 с двумя ожидаемыми assertions; GREEN — exit 0, два PASS,
12 layout cases. Chromium запускался с разрешённым browser IPC; локальный HTTP
сервер слушал только 127.0.0.1, внешние запросы блокировались.
Самопроверка и ZIP/manifest обновляются после отчёта; их актуальные результаты
хранятся в `selfcheck.json`, `recovery.json`, `sources/manifest.json`.

Полная независимая browser-перепроверка текущего snapshot ожидается от QA.
Предыдущее успешное/неуспешное evidence не переименовывается в текущую приёмку.
Реальные Android permission, TalkBack, push, unlock, APK, PO/G4/G5 остаются PENDING.
