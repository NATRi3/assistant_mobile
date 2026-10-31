#!/usr/bin/env python3
"""Rebuild editable design SVG and CSS using only Python's standard library."""
import json
from pathlib import Path
from html import escape
import argparse
import textwrap

ROOT = Path(__file__).resolve().parents[1]
TOKENS = json.loads((ROOT / 'tokens/semantic.json').read_text())
FIXTURES = json.loads((ROOT / 'sources/fixtures.json').read_text())
STATES = json.loads((ROOT / 'sources/state-map.json').read_text())
PENDING = 'ДИЗАЙН · СИНТЕТИЧЕСКИЙ ПРИМЕР'


class Canvas:
    def __init__(self, colors):
        self.c = colors
        self.parts = []

    def rect(self, x, y, w, h, fill='surface', radius=20, stroke=None):
        self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{self.c.get(fill, fill)}"'+(f' stroke="{self.c[stroke]}"' if stroke else '')+'/>')

    def text(self, x, y, value, size=16, fill='text', weight=400):
        self.parts.append(f'<text x="{x}" y="{y}" fill="{self.c.get(fill,fill)}" font-size="{size}" font-weight="{weight}">{escape(str(value))}</text>')

    def lines(self, x, y, value, width=32, size=16, fill='text', weight=400):
        lines = textwrap.wrap(value, width=width, break_long_words=False)
        for i, line in enumerate(lines):
            self.text(x, y + i * (size * 1.5), line, size, fill, weight)
        return y + len(lines) * size * 1.5

    def button(self, y, value, primary=True, x=24, w=364, disabled=False):
        self.rect(x,y,w,56,'soft' if disabled else 'primary' if primary else 'surface',16,'border' if not primary or disabled else None)
        self.text(x+20,y+35,value,16,'muted' if disabled else 'onPrimary' if primary else 'primary',600)

    def card(self, y, h=150, soft=False):
        self.rect(24,y,364,h,'soft' if soft else 'surface',24,'border')

    def svg(self, title, desc, width=412, height=892):
        return f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title description"><title id="title">{escape(title)}</title><desc id="description">{escape(desc)}</desc><g font-family="system-ui, sans-serif">'+''.join(self.parts)+'</g></svg>\n'


def screen(screen_id, theme, state='default', alternative=False):
    c = dict(TOKENS['semantic'][theme])
    if alternative:
        c.update(background='#FAF5EB',surface='#FFFCF5',text='#372B24',muted='#705D4F',primary='#81532F',onPrimary='#FFFFFF',soft='#F0E4D2',border='#947E68')
    height = 1012 if state in ('offline','stale','error','unknown','denied','channel-disabled','no-gms','expired') else 940
    footer = height - 80
    a = Canvas(c)
    a.rect(0,0,412,height,'background',0)
    a.rect(0,0,412,28,'soft',0)
    a.text(24,19,PENDING,10,'text',600)
    a.text(24,54,'09:41',14,'text',600)
    a.text(322,54,'●  ▰',14)
    a.text(24,101,'←',24)
    a.text(73,99,'Ассистент',18,'text',650)
    a.text(356,99,'☰',22)
    a.text(24,143,'СУББОТА · 31 ОКТЯБРЯ' if screen_id=='D02' else 'ЛИЧНЫЙ АССИСТЕНТ',11,'muted',650)
    a.text(24,184,STATES['screens'][screen_id]['name'],30,'text',650)
    y = 216
    banners={'offline':'Нет сети · данные на 09:40','stale':'Данные устарели · обновите','error':'Ошибка загрузки · попробуйте снова','unknown':'Результат неизвестен · проверьте','denied':'Уведомления не разрешены','channel-disabled':'Канал выключен в ОС','no-gms':'Push недоступен на устройстве','expired':'Срок действия истёк'}
    if state in banners:
        a.rect(24,y,364,52,'warningSurface',12)
        a.text(40,y+32,banners[state],14,'warning',600)
        y += 72
    if state=='revoked':
        a.card(y,220)
        a.text(48,y+40,'Доступ к данным закрыт',22,'text',650)
        a.lines(48,y+76,'Старые данные скрыты. Подключите этот телефон заново.',28,16)
        a.button(y+150,'Подключить телефон',x=48,w=316)
    elif state=='loading':
        a.card(y,196)
        a.text(48,y+48,'Подождите…',24,'text',650)
        a.lines(48,y+90,'Демонстрация ожидания. Запросы не выполняются.',28,16,'muted')
        a.button(y+224,'Отменить ожидание',False)
    elif state=='logout-unconfirmed':
        a.card(y,296)
        a.lines(48,y+42,'Телефон отключён здесь; серверный отзыв не подтверждён',25,22,'text',650)
        a.lines(48,y+158,'В доверенном Telegram-канале владельца отзовите этот телефон:',30,15,'muted')
        a.text(48,y+229,'/mobile_revoke',14,'primary',600)
        a.text(48,y+259,'00000000-0000-4000-8000-000000000083',12,'text')
        a.text(24,y+340,'Device ID синтетический · не токен',13,'muted')
        a.button(y+376,'Привязка после отзыва владельцем',False,disabled=True)
    elif screen_id=='D01':
        a.text(24,y+20,'Ваш телефон. Ваши дела.',24,'text',650)
        a.lines(24,y+58,'Подтвердите подключение в уже доверенном канале владельца.',32)
        a.card(y+140,160)
        a.text(48,y+178,'ПРИМЕР ПРИВЯЗКИ',11,'muted',650)
        a.text(48,y+217,'DEMO',30,'primary',650)
        a.text(48,y+255,'Не код доступа · без credentials',14,'muted')
        a.button(y+328,'Показать привязку · пример')
        a.button(y+396,'Отмена',False)
        a.lines(24,y+488,'Пароли, bot tokens и реальные данные не нужны для просмотра макета.',37,13,'muted')
    elif screen_id=='D02':
        a.text(24,y+8,'Обновлено в 09:40 · UTC+03:00, пример',13,'muted')
        if state=='empty':
            a.card(y+36,196)
            a.text(48,y+80,'На сегодня дел нет',24,'text',650)
            a.lines(48,y+124,'Задачи и напоминания появятся из вашего owner-канала.',28,16,'muted')
        else:
            a.card(y+36,250,True)
            a.text(48,y+75,'СЕГОДНЯ',11,'muted',650)
            a.text(48,y+129,'10:00',40,'text',650)
            a.lines(48,y+170,'Ближайшее напоминание',24,22,'text',650)
            a.button(y+208,'Открыть напоминание',False,x=48,w=316)
            a.text(24,y+328,'Задачи',24,'text',650)
            a.text(298,y+326,'2 открыто',13,'muted')
            a.card(y+350,100)
            a.lines(48,y+386,'Подготовить список покупок',28,16,'text',600)
            a.text(48,y+425,'Открытая задача                  ↗',14,'muted')
            if state=='default':
                a.card(y+462,100)
                a.text(48,y+500,'Открыть напоминание',16,'text',600)
                a.text(48,y+536,'Напоминание на сегодня           ↗',14,'muted')
    elif screen_id=='D03':
        a.rect(288,y,48,48,'primary',16)
        a.text(303,y+33,'↗',24,'onPrimary')
        a.rect(70,y+64,318,94,'soft',20,'border')
        a.text(90,y+94,'Вы',13,'muted')
        a.lines(90,y+126,'Что у меня запланировано?',29)
        a.card(y+174,185)
        a.text(48,y+208,'Ассистент · пример ответа',13,'muted')
        a.lines(48,y+246,'В примере две задачи. Ближайшее напоминание — в 10:00. Детали доступны в «Сегодня».',29)
        a.text(24,y+400,'Сообщение',16,'text',600)
        a.rect(24,y+416,364,86,'surface',16,'border')
        a.text(40,y+451,'Введите текст примера…',16,'muted')
        a.button(y+518,'Проверить результат' if state=='unknown' else 'Отправить пример',disabled=state=='offline')
        a.text(24,y+602,'Фиксированный ответ · без AI',13,'muted')
    elif screen_id in ('D04','D05'):
        task=screen_id=='D04'
        done=state in ('done','snoozed')
        a.card(y,238)
        a.text(48,y+38,'СУЩЕСТВУЮЩАЯ ЗАДАЧА' if task else 'ПОДТВЕРЖДЁННОЕ НАПОМИНАНИЕ',10,'muted',650)
        a.lines(48,y+88,'Подготовить список покупок' if task else 'Позвонить в мастерскую',23,24,'text',650)
        a.text(48,y+168,('Завершена' if done else 'Открыта') if task else ('Сегодня, 10:10' if done else 'Сегодня, 10:00'),18)
        a.text(48,y+205,'Версия примера · обновлено 09:40',13,'muted')
        if done:
            a.rect(24,y+262,364,62,'soft',12)
            a.text(40,y+299,'Завершено в примере' if task else 'Отложено на 10 минут в примере',15,'text',600)
        else:
            a.lines(24,y+280,'Команда требует актуальной версии, авторизации и сети.',34,15,'muted')
        a.button(y+352,'Завершить задачу' if task else 'Отложить на 10 минут',disabled=state in ('offline','stale','error','unknown') or done)
        a.button(y+420,'Проверить результат' if state=='unknown' else 'К «Сегодня»',False)
        a.lines(24,y+518,'Повтор не создаёт второй эффект. Реальные команды не отправляются.',37,13,'muted')
    elif screen_id=='D06':
        a.card(y,172)
        a.text(48,y+42,'Состояние связи',22,'text',650)
        a.text(48,y+84,'Последнее обновление: 09:40',16)
        a.lines(48,y+122,'Данные примера. ОС не опрашивается.',32,14,'muted')
        a.card(y+192,180)
        a.text(48,y+236,'Уведомления',22,'text',650)
        a.text(48,y+278,'Канал «Напоминания»',16)
        a.lines(48,y+316,'Показ не означает прочтение человеком.',31,14,'muted')
        a.button(y+404,'Настройки уведомлений',False)
        a.text(24,y+504,'Без inbox и истории прочтений',13,'muted')
    elif screen_id=='D07':
        a.card(y,128)
        a.text(48,y+40,'Полезные напоминания',19,'text',650)
        a.text(48,y+80,'Всегда нейтральный текст',14,'muted')
        a.card(y+144,110)
        a.text(48,y+184,'Тихие часы',19,'text',650)
        a.text(48,y+222,'22:00–08:00 · UTC+03:00',16)
        a.card(y+270,142)
        a.text(48,y+311,'Сводка в виджете',19,'text',650)
        a.lines(48,y+347,'Только число задач и ближайшее время. Видны на домашнем экране.',32,14,'muted')
        a.button(y+444,'Связь и разрешения',False)
        a.button(y+512,'Этот телефон и выход',False)
        a.lines(24,y+594,'Ранее отменённые уведомления не повторяются; напоминания остаются в списке.',43,13,'muted')
    elif screen_id=='D08':
        a.card(y,140)
        a.text(48,y+46,'Этот телефон',24,'text',650)
        a.text(48,y+88,'Привязан к владельцу · пример',15,'muted')
        a.lines(24,y+188,'Выход скрывает локальные данные. Отзыв на сервере прекращает будущий доступ.',32)
        a.button(y+316,'Отозвать этот телефон',False)
        a.button(y+384,'Выйти на этом телефоне',False)
        a.lines(24,y+492,'Потерянный телефон отзывается через доверенный owner-канал. Offline wipe не гарантируется.',37,13,'muted')
    elif screen_id=='D09':
        a.text(24,y+8,'СИСТЕМНЫЕ ПОВЕРХНОСТИ · ПРИМЕР',10,'muted',650)
        a.card(y+32,190)
        a.text(48,y+69,'Ассистент · Напоминания',13,'muted')
        a.lines(48,y+111,'Пора проверить напоминание',28,18,'text',650)
        a.rect(48,y+150,316,48,'soft',12,'border')
        a.text(64,y+180,'Открыть        Отложить 10 мин',14,'primary',600)
        a.text(24,y+266,'ДОМАШНИЙ ВИДЖЕТ',11,'muted',650)
        a.card(y+290,186)
        a.text(48,y+334,'Ассистент',22,'text',650)
        a.text(48,y+376,'2 задачи · ближайшее 10:00' if state=='summary' else 'Открыть приложение',16)
        a.text(48,y+415,'Данные устарели · 09:40' if state in ('offline','stale') else 'Обновлено в 09:40',13,'muted')
        a.text(48,y+450,'↗ Открыть через unlock',14,'primary',600)
        a.lines(24,y+526,'Opt-in только count и time. Приватных текстов нет ни в push, ни в виджете.',38,13,'muted')
    a.rect(0,footer,412,80,'surface',0)
    a.rect(24,footer+12,174,48,'soft' if screen_id=='D02' else 'surface',16)
    a.rect(214,footer+12,174,48,'soft' if screen_id=='D03' else 'surface',16)
    a.text(73,footer+42,'Сегодня',16,'text' if screen_id=='D02' else 'muted',600)
    a.text(266,footer+42,'Диалог',16,'text' if screen_id=='D03' else 'muted',600)
    return a.svg(f'{screen_id} · {STATES["screens"][screen_id]["name"]} · {theme} · {state}',f'{PENDING}. Направление {"B: тёплый дневник" if alternative else "A: Тихий рабочий стол"}. Состояние {state}. Редактируемые текстовые и векторные слои; не приложение.',height=height)


VARIANTS={'D01':['expired','logout-unconfirmed'],'D02':['loading','empty','offline','stale','error'],'D03':['unknown'],'D04':['done'],'D05':['offline','stale','unknown','snoozed'],'D06':['denied','no-gms'],'D08':['revoked'],'D09':['summary','stale']}


def outputs():
    files={}
    for theme in ('light','dark'):
        for sid in STATES['screens']:
            files[f'screens/{sid}-{theme}.svg']=screen(sid,theme)
            for state in VARIANTS.get(sid,[]):
                files[f'screens/{sid}-{state}-{theme}.svg']=screen(sid,theme,state)
    files['screens/direction-B-today.svg']=screen('D02','light',alternative=True)
    css=[]
    for theme,colors in TOKENS['semantic'].items():
        selector=':root, [data-theme="light"]' if theme=='light' else '[data-theme="dark"]'
        css.append(selector+'{'+''.join(f'--{key}:{value};' for key,value in colors.items())+'}')
    css.append((ROOT/'preview/layout.css').read_text())
    files['preview/review.css']='\n'.join(css)
    a=Canvas(TOKENS['semantic']['light'])
    a.rect(0,0,1120,700,'background',0)
    a.text(32,50,'Первый полезный путь',32,'text',650)
    a.text(32,84,'Синтетический дизайн-flow · AS-83 · A / Тихий рабочий стол',15,'muted')
    nodes=[(32,120,'D01 · Подключить','Доверенный owner-канал'),(402,120,'D02 · Сегодня','Существующие Task/Reminder'),(772,120,'D04 · Завершить','Явная команда · свежая версия'),(32,310,'D09 · Generic push','Нет названий или source text'),(402,310,'Unlock → fresh fetch','Device/session/expiry/version'),(772,310,'D05 · Snooze 10 мин','Одна новая версия Reminder'),(32,500,'D03 · Текстовый диалог','Ожидание / ошибка / unknown'),(402,500,'D09 · Малый виджет','Opt-in только count/time'),(772,500,'D08 · Logout/revoke self','Локальное скрытие, серверный отзыв')]
    for x,y,title,copy in nodes:
        a.rect(x,y,316,132,'surface',20,'border')
        a.text(x+20,y+40,title,18,'text',650)
        a.lines(x+20,y+78,copy,31,14,'muted')
    for y in (191,381,571):
        for x in (356,726):a.text(x,y,'→',24,'primary',650)
    a.text(32,671,'Offline/stale: команды заблокированы. Unknown: сначала сверка. Отзыв не обещает удалённый offline wipe.',14,'muted')
    files['flows/golden-flow.svg']=a.svg('Первый полезный путь','Редактируемая схема потоков и безопасных переходов Android MVP.',1120,700)
    return files


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    files=outputs()
    if args.check:
        mismatches=[p for p,s in files.items() if not (ROOT/p).exists() or (ROOT/p).read_text()!=s]
        print(json.dumps({'generated_files':len(files),'mismatches':mismatches}));return bool(mismatches)
    for p,s in files.items():
        dest=ROOT/p;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(s)
    print(json.dumps({'written':len(files)}))
    return 0


if __name__=='__main__':raise SystemExit(main())
