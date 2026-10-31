# Handoff · AS-83 · 0.1.0-review

Источник scope: AS-80/AS-83, локальные `planning/analyst-draft.md` §§2/6–9 и scoped
designer brief. Уточнение координатора: A «Тихий рабочий стол», Android-first,
SVG editable originals + генератор/токены/clickable preview/manifest/ZIP restore
приняты обновлённым AS-83 AC3 как первый переносимый комплект. Penpot не подключён
и остаётся необязательным будущим рабочим полотном.
Роль автора — Product Designer; это не функциональный QA и не независимый G5.

## Что можно оценить сейчас

Согласованные по содержанию светлая/тёмная темы, девять экранных семейств,
безопасные ветви, два сравнительных направления и кликабельный локальный flow.
Тон спокойный: одна эмблема-стрелка, явное главное действие, дата/last-sync,
статус текстом. Декоративного персонажа и шумных советов нет.
Системный шрифт с кириллицей; шрифтовых файлов/сети не требуется.

`tokens/semantic.json` → `sources/build.py` → SVG и `preview/review.css`.
`preview/layout.css` — исходник геометрии HTML. `review.js` — только демонстрационное
состояние в памяти страницы, без storage, service worker, network API или AI.
Изменение JSON-токена требует regenerate + selfcheck + review новой версии.

## Экраны, состояния и связь с будущими контрактами

| Экран | Действия / контракт аналитики | Состояния / evidence в комплекте |
|---|---|---|
| D01 Подключение | Future pairings + trusted owner approve + proof of device key. Здесь кнопка только демонстрирует успех | SVG base/expired, HTML loading/denied/error/revoked. `DEMO` не настоящий challenge |
| D02 Сегодня | GET dashboard; Task titles только из собственных Task projections после unlock. ReminderSummary только id/due_at/version/source_warning: generic «Ближайшее напоминание»/«Открыть напоминание», без текста Reminder и linked_task_id | SVG loading/empty/offline/stale/error обе темы; HTML дополнительно revoked |
| D03 Диалог | Typed mobile origin, client_message_id, bounded owner text/reply; не synthetic Telegram IDs | SVG base/unknown; HTML loading/error/retry/cancel/offline/empty/revoked. Фиксированный ответ, без настоящей генерации |
| D04 Task | GET current task → explicit complete с expected_version + Idempotency-Key | SVG base/done; HTML offline/stale/error/unknown/deleted/revoked; без CRUD/undo promise |
| D05 Reminder | GET fresh notification/reminder → explicit snooze10m с expected_version + Idempotency-Key | SVG base/offline/stale/unknown/snoozed обе темы; HTML также expired/deleted/revoked |
| D06 Статус | Device transport/OS/channel state и last-sync, переход к настройкам | SVG denied/no-GMS; HTML offline/stale/channel-disabled/error/loading/revoked. Нет inbox/read API |
| D07 Настройки | GET/PATCH preferences: mobile opt-in, общий quiet policy/timezone, widget summary; app/OS состояния отдельно | HTML denied/channel-disabled/no-GMS/offline/error/revoked. Одна продуктовая категория «Напоминания», выбор mobile/Telegram/both сам не меняется при установке |
| D08 Этот телефон | DELETE devices/self + local logout; remote lost-device revoke через trusted owner-канал | SVG base/revoked; HTML offline/error/loading/revoked. Никакого списка других устройств |
| D09 Push/widget | Generic opaque notification → app unlock → authenticated fresh fetch → D05; widget → unlock → dashboard | SVG base/summary/stale обе темы; HTML denied/offline/revoked. Никакой команды при render или при одном tap на notification |

Полный inventory машинно читается в `sources/state-map.json`; подписи в HTML
совпадают с ним. Все ручные состояния помечены макетом, а не реальной диагностикой
операционной системы. В основном flow Task/Reminder предварительно созданы через
уже доверенный owner-канал, а не появляются от клика по ответу модели.

## Кликабельные проверки для независимого review

1. D01 → «Показать успешную привязку» → демонстрационный диалог → D02.
   Никакого ввода credentials. Отмена оставляет предыдущий контекст.
2. D02 → задача → «Завершить задачу» → подтверждение → D04 done → D02.
   В примере состояние меняется один раз, повтор disabled.
3. D09 → «Отложить 10 мин» → отдельный шаг unlock → отдельный шаг fresh fetch →
   D05 → явная команда «Отложить на 10 минут» → подтверждение → 10:10/новая версия.
   Исходный notification tap не делает snooze. Это схема, не настоящий app unlock.
4. Выбрать D05 offline: CTA disabled, кеш имеет время. D05 stale: сначала refresh.
   D05 unknown: CTA disabled, «Проверить результат» показывает итог без новой команды.
5. D03: набрать текст → «Отправить пример» → ожидание → фиксированный ответ.
   Отмена не притворяется остановкой удалённой модели; в реальном API cancel
   семантика требует G2. Unknown сначала reconcile, не повторная генерация.
6. D07 widget opt-in → D09: только «2 задачи · ближайшее 10:00» и last-sync.
   Названия/источники/контакты/диалог отсутствуют. Toggle off возвращает generic.
7. D08 logout/revoke → подтверждение → D01. D09 после этого показывает очищенные
   локальные уведомления и «Подключите телефон», без summary. Re-pair — отдельный шаг.
   При D08 offline → logout экран D01 явно показывает «Телефон отключён здесь;
   серверный отзыв не подтверждён» и инструкцию `/mobile_revoke DEVICE_UUID` в
   доверенном Telegram-канале владельца. Device UUID синтетический, без токенов.
   Успешный server revoke не изображается; ветка не разрешает новую привязку до
   owner revoke. В review начать другой независимый сценарий можно кнопкой сброса.
8. Темы + 130/200% → пройти D02/D03/D05/D07; фокус и кнопки доступны клавиатурой.
   После двух найденных QA-дефектов точечные browser-регрессии и их RED/GREEN
   записаны в `evidence/defect-fixes.md`; полный независимый rerun ещё требуется.

## Приватность и сообщения об ошибках

Push во всех темах/состояниях всегда «Пора проверить напоминание»; payload не содержит
task title, contact/source text/chat, credentials или полномочия выполнить команду.
Внешний link/opaque ID — недоверенный вход. Реальная реализация проверяет session,
owner/device scope, expiry и текущую версию на сервере, даже если UI уже подтвердили.
Приватные данные получают только после unlock + authenticated fetch.

Dashboard не читает Reminder detail text и не подменяет его названием связанной
задачи: ReminderSummary не содержит text/title/linked_task_id. Приватный текст
Reminder остаётся только D05 после unlock и запроса Reminder detail. Название Task
в D02 разрешено только из собственной Task projection, а не из Reminder.

В реализации одна продуктовая категория «Напоминания» имеет два системных канала:
`reminders_v1` — обычное поведение под контролем пользователя ОС;
`reminders_fallback_v1` — silent generic fallback. Fallback не раскрывает деталей;
он может иметь только «Открыть», без обещания snooze-кнопки. Quiet preferences
управляют серверной отправкой и проверкой callback; они не меняют автоматически
user-controlled importance/sound существующего OS channel. В обычном экране
достаточно «Полезные напоминания»/«Всегда нейтральный текст» и ссылки на системные
настройки; техническое разделение каналов — handoff native adapter.

D07 help: «Ранее отменённые уведомления не повторяются; напоминания остаются в
списке». После route off→on отменённый intent той же пары ReminderVersion/device
version не восстанавливается и не backfill-ится. Сам Reminder виден в списке;
snooze/другая новая версия Reminder может создать новый intent. Это пояснение
существующей настройки, не новый UI inbox/повтор старых отправок.

Виджет по умолчанию generic. Opt-in разрешает только число незавершённых задач,
время ближайшего напоминания и last-sync. Тексты запрещены даже после opt-in.
Launcher не считается приватным экраном. Lock-state detection и точное обновление
не обещаются. Несколько instances получают одинаковую политику очистки.

Logout немедленно скрывает локальные проекции/виджет/уведомления. Server revoke
блокирует доступ после серверного подтверждения; уже отключённый телефон получит
отзыв при контакте. Удалённое offline wipe не обещается. Срок cached private view
фиксирует G2; credentials/cache исключаются из device backup/transfer в реализации.
При offline/timeout локальный logout не объявляет server success: видимое сообщение
о неподтверждённом отзыве и owner Telegram instruction остаются после очистки ключей.

Offline — чтение явно помеченного кеша, без скрытой очереди mutation. Stale —
обновление и новое осмысленное действие. Deleted/forbidden — одинаковое нейтральное
объяснение. Unknown — сверка, без ложного «готово» и blind retry. Значения времени
в макете синтетические; timezone подписана. ОС может задерживать push/refresh;
provider_accepted не означает shown/read и не обещает exactly-once звук.

## Доступность и компоненты

HTML: `<button>`/`select`/`textarea`, focus-visible outline 3 px + 3 px offset,
min target 48 px, главные CTA 56 dp/px, перенос текста без фиксированной высоты,
семантические заголовки/labels/role=status. Иконки имеют accessible names,
декоративная эмблема aria-hidden. Два раздела сохраняют Back context и draft.
SVG — редактируемый визуальный handoff, не семантическое дерево Android.

Числовой контраст измеряется по всем перечисленным парам токенов в обеих темах;
evidence содержит фактические ratios. Запрещено заменять статус одним цветом.
Dynamic color пока не включён: потребуется отдельная матрица фактических пар.
Low motion по умолчанию: нет перемещений/пульсации; opt-in motion допускает только
200 ms opacity, `prefers-reduced-motion` имеет приоритет. Нет haptic/audio-only
сигналов. TalkBack order/announcements и 200% font на реальном Android — PENDING.

Геометрия SVG: 412 dp шириной; базовые кадры 940 dp, состояния с баннером 1012 dp.
Это длинные review frames, а не обещание уместить весь экран без прокрутки на 360 dp.
HTML reflow и scroll — основа проверки узких экранов; ширина 320/360/412/600 dp,
landscape и клавиатура должны быть проверены QA. Длинная кириллица не сокращается
в опасных CTA; task title допускает перенос. Два раздела не требуют трёхэлементной
bottom nav. Синтетическая стилизация statusbar не копирует точную ОС.

## Оригиналы, перенос и восстановление

Editable sources — настоящие SVG `<text>/<rect>` и генератор, JSON/CSS/HTML/JS.
Нет `.fig`/`.penpot`, потому что реальный workspace не подключён.
`sources/review-source.zip` и `evidence/recovery.json` подтверждают только ZIP restore
этих файлов с проверкой SHA256. Отдельно `build.py --check` подтверждает
детерминированное восстановление SVG/CSS из локальных исходников.
Это не проверка Penpot-import, совместимости библиотек или реального cloud backup.

Если позднее будет выбран и подключён Penpot, импортировать SVG в отдельный тестовый проект и проверить
редактируемый кириллический текст/формы/компоненты, экспорты и сохранение цветов.
Не приписывать импортированному SVG автоматически созданные shared components.
Версию, frame links, editable `.penpot` export и настоящее восстановление записать
в manifest только по результатам. AS-83 AC3 теперь принимает текущий SVG-комплект
с генератором/токенами/preview/SHA/ZIP restore; отсутствие опционального Penpot-import
не блокирует первый MVP и не считается выполненным импортом.

После foundation перенос в private mobile `design/`: tokens + approved export version
в Git; большие future editable archives через LFS/private Release с SHA256.
Не держать два расходящихся master. Любое изменение после QA требует повторной
проверки затронутых состояний; G5 привязывается к финальному commit SHA.

## Статус передачи

Артефакты созданы, selfchecks описаны в `evidence/selfcheck.json`; локальный дизайн
готов к повторному независимому review. Точечные browser-регрессии двух дефектов
прошли, evidence — `evidence/defect-fixes.md`. PO final acceptance, полный текущий
независимый browser visual/keyboard review,
Android TalkBack/permission/widget/push runtime, G4 и G5 — PENDING. Penpot-import
не выполнялся и остаётся необязательным будущим шагом.
Ни APK, ни настоящий push, ни внешний workspace/repo/deploy этим комплектом не созданы.
