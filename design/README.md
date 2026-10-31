# Тихий рабочий стол · AS-83

Версия `0.1.0-review`, 31.10.2026. Реальные локальные дизайн-артефакты для первого
Android MVP: существующие Task/detail/complete, Reminder/snooze10m, визуальный
owner-диалог, pairing, настройки/self-device, generic push и малый count/time widget.
Данные синтетические. Это дизайн-прототип, без приложения, сети, AI и backend.

Открыть [интерактивный прототип](preview/index.html), [два направления](directions.html),
[схему первого пути](flows/golden-flow.svg) и [handoff](handoff.md).
HTML использует только соседние CSS/JS, работает локально; сеть запрещена CSP.
Если просмотрщик блокирует local scripts, из этого каталога запустить
`python3 -m http.server 8765 --bind 127.0.0.1` и открыть локальный
`http://127.0.0.1:8765/preview/index.html`. Это временный preview, не публикация сайта.

Направление A «Тихий рабочий стол» выбрано координатором для первого обратимого
среза. Направление B — сравнительный концепт «Тёплый личный дневник».
Финальная приёмка PO, G4 и G5 этим выбором не объявляются.

## Файлы

- `screens/`: 55 редактируемых SVG: D01–D09 в light/dark, негативные/результирующие
  варианты и один сравнительный B. Текст остаётся `<text>`, формы — векторами;
  внешних ссылок, bitmap и встроенных шрифтов нет.
- `tokens/semantic.json`: цвета двух тем, роли, контрастные пары, типографика,
  сетка, цели касания и low-motion.
- `sources/fixtures.json`, `sources/state-map.json`: синтетический контент и
  flow/state/action mapping.
- `sources/build.py`: воспроизводимый генератор SVG/CSS; `--check` сравнивает
  генерируемые файлы с текущими.
- `preview/`: интерактивная DOM-демонстрация с темами, 100/130/200% текстом и
  ручным выбором негативных состояний.
- `sources/verify.py`, `evidence/`: локальная проверка, результаты и настоящее
  восстановление из ZIP с проверкой SHA256. Это SVG recovery, не Penpot import.
- `sources/manifest.json`: реальный путь/хеш/version для каждого локального
  артефакта; финальная PO acceptance остаётся PENDING. Penpot — необязательный
  последующий инструмент, сейчас не подключён.

Проверить: `python3 sources/build.py --check`, затем `python3 sources/verify.py`.
Генерация: `python3 sources/build.py`; проверка обновляет evidence и manifest.
`sources/review-source.zip` содержит приватный локальный снимок исходников/экспортов,
из которого проверен byte-for-byte restore. Публикации внешнего Release/LFS нет.

## Границы

Кандидаты AS-74/create/edit/confirm остаются в Telegram. Mobile candidate CRUD,
notification inbox/read history, другие устройства и private push/widget previews
— future, без новых скрытых backend promises. Фиксированный ответ чата не является
настоящим AI; кнопка «Привязать» не создаёт owner session.

Penpot workspace не подключён. Editable originals здесь — SVG и их генератор;
выдуманных `.penpot`/`.fig` нет. Обновлённый AS-83 AC3 принимает editable SVG,
генератор, токены, clickable preview, manifest/SHA и проверенный ZIP restore как
первый переносимый комплект. Penpot-import/editability/restore — необязательный
будущий шаг после подключения workspace, не prerequisite первого MVP. После AS-86
перенести комплект в private `assistant_mobile/design` с сохранением manifest.
Source of truth handoff — versioned tokens + принятая версия export в Git; если
Penpot будет выбран позднее, его рабочее полотно не создаёт второй несогласованный master.

Выполнены перечисленные в evidence локальные selfchecks и
[точечные browser-регрессии двух QA-дефектов](evidence/defect-fixes.md).
Полный независимый browser rerun текущей версии, реальный TalkBack, системное
разрешение Android, push, APK и G4/G5 требуют отдельного evidence.
