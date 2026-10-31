#!/usr/bin/env python3
"""Local artifact checks; never labels static evidence as browser or Android QA."""
import hashlib
import importlib.util
import json
import re
import subprocess
import tempfile
import zipfile
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
EVIDENCE=ROOT/'evidence'
NS={'s':'http://www.w3.org/2000/svg'}


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def dump(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
def luminance(value):
    colors=[int(value[i:i+2],16)/255 for i in (1,3,5)]
    linear=[c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in colors]
    return sum(a*b for a,b in zip(linear,[.2126,.7152,.0722]))


class ReviewParser(HTMLParser):
    def __init__(self):super().__init__();self.links=[];self.buttons=[];self.labels=[];self.inputs=[];self.has_csp=False
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        for key in ('src','href'):
            if key in a:self.links.append(a[key])
        if tag=='button':self.buttons.append(a)
        if tag=='label':self.labels.append(a)
        if tag in ('input','textarea','select'):self.inputs.append(a)
        if tag=='meta' and a.get('http-equiv')=='Content-Security-Policy':self.has_csp="connect-src 'none'" in a.get('content','')


def main():
    EVIDENCE.mkdir(exist_ok=True)
    checks=[];limits=[];contrast=[]
    def check(name,condition,detail):checks.append({'check':name,'result':'PASS' if condition else 'FAIL','detail':detail})
    all_json=list(ROOT.rglob('*.json'))
    for path in all_json:json.loads(path.read_text())
    check('JSON parse',True,f'{len(all_json)} current JSON files parsed')
    tokens=json.loads((ROOT/'tokens/semantic.json').read_text())
    mapping=json.loads((ROOT/'sources/state-map.json').read_text())
    fixtures=json.loads((ROOT/'sources/fixtures.json').read_text())
    for theme,colors in tokens['semantic'].items():
        for pair in tokens['contrastPairs']:
            light,dark=sorted([luminance(colors[pair['foreground']]),luminance(colors[pair['background']])],reverse=True)
            ratio=(light+.05)/(dark+.05)
            contrast.append({'theme':theme,**pair,'ratio':round(ratio,4),'pass':ratio>=pair['minimum']})
    check('Semantic contrast',all(p['pass'] for p in contrast),f'{len(contrast)} pairs; numeric AA text/control thresholds only, not a rendered audit')
    check('Synthetic fixtures',fixtures.get('synthetic') is True and fixtures['challenge']=='DEMO · НЕ КОД ДОСТУПА','No actual credentials or owner content')
    check('Privacy token policy',not tokens['component']['notification']['privateText'] and not tokens['component']['widget']['privateText'] and tokens['component']['widget']['optInFields']==['open_task_count','nearest_reminder_time','last_sync'],'Generic push; widget count/time/last_sync only')
    svgs=list((ROOT/'screens').glob('*.svg'))+list((ROOT/'flows').glob('*.svg'))
    external=[];geometry=[];missing=[]
    for path in svgs:
        tree=ET.parse(path);root=tree.getroot();w=float(root.attrib['width']);h=float(root.attrib['height'])
        if root.find('s:title',NS) is None or root.find('s:desc',NS) is None:missing.append(path.name)
        for node in root.iter():
            if node.tag.endswith(('image','script','foreignObject')):external.append(path.name)
            for key,val in node.attrib.items():
                if key.endswith('href') and not val.startswith('#'):external.append(path.name)
            if node.tag.endswith('rect'):
                x,y,rw,rh=[float(node.attrib.get(k,0)) for k in ('x','y','width','height')]
                if min(x,y,rw,rh)<0 or x+rw>w+.01 or y+rh>h+.01:geometry.append((path.name,'rect bounds'))
            if node.tag.endswith('text'):
                x,y=[float(node.attrib.get(k,0)) for k in ('x','y')]
                if not (0<=x<=w and 0<=y<=h):geometry.append((path.name,'text origin bounds'))
    check('SVG XML/editable layers',not external and not missing,f'{len(svgs)} SVG parsed; title/desc present, no raster/external refs/script/foreignObject')
    check('SVG coordinate bounds',not geometry,geometry or 'All vector rectangles and text origins inside frames; glyph extents/rendering not verified')
    check('Nine screens in two themes',all((ROOT/f'screens/{sid}-{theme}.svg').is_file() for sid in mapping['screens'] for theme in ('light','dark')),'D01–D09 base frames exist')
    check('Minimum targets',tokens['component']['button']['minTargetDp']>=48 and 'min-height:48px' in (ROOT/'preview/layout.css').read_text(),'Token + CSS minimum 48; main buttons 56. Actual rendered target bounds pending browser/Android QA')
    broken=[];network=[]
    for path in [ROOT/'preview/index.html',ROOT/'directions.html']:
        parser=ReviewParser();parser.feed(path.read_text())
        for link in parser.links:
            if re.match(r'https?://|//',link):network.append(link)
            elif not (path.parent/link.split('#')[0]).exists():broken.append(str(path.relative_to(ROOT))+':'+link)
        check(f'CSP {path.name}',parser.has_csp,'connect-src none; no remote resources')
    for path in ROOT.rglob('*.md'):
        for link in re.findall(r'\]\(([^)]+)\)',path.read_text()):
            if not re.match(r'https?://|#',link) and not (path.parent/link.split('#')[0]).exists():broken.append(str(path.relative_to(ROOT))+':'+link)
    check('Local links/resources',not broken and not network,broken or 'HTML/CSS/JS/images/Markdown references resolve; no HTML remote resources')
    js=(ROOT/'preview/review.js').read_text()
    check('No network or persistence API',not re.search(r'\b(fetch\s*\(|XMLHttpRequest|WebSocket|EventSource|sendBeacon|localStorage|sessionStorage|indexedDB|serviceWorker)\b',js),'JS inspection plus CSP; not a dynamic network trace')
    check('States match HTML JS mapping',all(f"{sid}:[" in js and all("'"+state+"'" in re.search(rf'{sid}:\[([^\]]+)\]',js).group(1) for state in meta['states']) for sid,meta in mapping['screens'].items()),'Machine state map and prototype state lists agree')
    reminder_text=fixtures['reminder_detail']['text']
    dashboard_svgs=list((ROOT/'screens').glob('D02-*.svg'))+[ROOT/'screens/direction-B-today.svg']
    dashboard_js=js.split("case'D02':",1)[1].split("case'D03':",1)[0]
    leaked=[p.name for p in dashboard_svgs if reminder_text in ' '.join(ET.parse(p).getroot().itertext())]
    summary=fixtures['dashboard']['reminder_summary']
    check('D02 ReminderSummary never exposes detail text',not leaked and reminder_text not in dashboard_js and set(summary)=={'id','due_at','version','source_warning'},f'{len(dashboard_svgs)} D02/A/B light/dark/state SVG frames plus HTML branch checked; fixture summary has no text/title/linked_task_id; D05 retains detail text')
    check('Offline logout visibly unconfirmed',all(s in js for s in ["localOnly?'logout-unconfirmed':'default'",'Телефон отключён здесь; серверный отзыв не подтверждён','/mobile_revoke 00000000-0000-4000-8000-000000000083',"state==='logout-unconfirmed'"]) and all((ROOT/f'screens/D01-logout-unconfirmed-{t}.svg').exists() for t in ('light','dark')),'After local clear, D01 warning/instruction persists; no offline server success; synthetic device ID only')
    check('Notification category/channel distinction','Один канал.' not in js and 'Одна продуктовая категория' in (ROOT/'handoff.md').read_text() and all(s in (ROOT/'handoff.md').read_text() for s in ['reminders_v1','reminders_fallback_v1','не меняют автоматически']),'Product UI says useful reminders; native handoff keeps ordinary/silent channels distinct and preserves OS-controlled importance/sound')
    check('Flow map resolvable',all(step.split(':')[0] in mapping['screens'] for flow in mapping['flows'] for step in flow['steps'] if re.match(r'D\d\d:',step)),'F01–F07 reference real screen IDs; action guards inspected statically')
    check('Mutation guards + replay handling',all(s in js for s in ["['offline','stale','error','unknown','revoked','loading'].includes(s)","model.complete=true","model.snoozed=true","case'reconcile'","const blocked=['offline','stale','error','unknown'].includes(state)||done"]),'Offline/stale/unknown guards, completion/snooze flags and reconcile handlers present; static, not runtime execution')
    check('Unlock/fetch distinct from mutation',"case'push-open':case'push-snooze':case'widget-open':promptAction('Шаг 1" in js and "promptAction('Шаг 2" in js and "После unlock/fetch выберите действие отдельно." in js,'Push routes to current detail; command requires separate button/confirmation')
    check('Logout clears local projection',all(s in js for s in ['model.linked=false','model.widget=false','model.reply=false',"model.draft=''",'Локальные уведомления очищены.']),'HTML memory projection clears and D09 hides notification/summary; no actual Android wipe claimed')
    check('Reduced motion + Cyrillic',"@media(prefers-reduced-motion:reduce)" in (ROOT/'preview/layout.css').read_text() and 'lang="ru"' in (ROOT/'preview/index.html').read_text(),'Default low motion; system fonts, RU language. Rendering/glyph availability not verified')
    generated=subprocess.run(['python3',str(ROOT/'sources/build.py'),'--check'],capture_output=True,text=True)
    check('Deterministic rebuild',generated.returncode==0,generated.stdout.strip() or generated.stderr.strip())
    content=[p for p in ROOT.rglob('*') if p.is_file() and 'evidence' not in p.relative_to(ROOT).parts and p.name not in ('manifest.json','review-source.zip') and '__pycache__' not in p.parts]
    archive=ROOT/'sources/review-source.zip'
    with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED) as out:
        for p in sorted(content):out.write(p,p.relative_to(ROOT))
    recovered=[]
    with tempfile.TemporaryDirectory(prefix='as83-svg-restore-') as directory:
        with zipfile.ZipFile(archive) as backup:backup.extractall(directory)
        for p in sorted(content):
            restored=Path(directory)/p.relative_to(ROOT)
            recovered.append({'path':str(p.relative_to(ROOT)),'sha256':sha(p),'restored_same_sha256':sha(p)==sha(restored)})
    check('Actual SVG/source ZIP recovery',all(p['restored_same_sha256'] for p in recovered),f'{len(recovered)} files exported, extracted to fresh temporary directory and SHA256 compared. Not Penpot import.')
    now=datetime.now(timezone.utc).isoformat()
    dump(EVIDENCE/'recovery.json',{'checked_at':now,'archive':'sources/review-source.zip','archive_sha256':sha(archive),'method':'ZIP export → fresh temporary directory → per-file SHA256; SVG/CSS separately deterministic rebuild','result':'PASS' if all(p['restored_same_sha256'] for p in recovered) else 'FAIL','penpot_import':'NOT_PERFORMED_OPTIONAL: workspace unavailable; not a prerequisite of updated AS-83 AC3','files':recovered})
    limits=[{'control':k,'result':'PENDING','reason':v} for k,v in [
        ('Independent browser rerun/current snapshot','Designer targeted browser regressions passed for permission cancellation and navigation at 200%; prior independent QA found these defects on older hashes; full independent current-snapshot rerun required'),
        ('Other JavaScript runtime keyflows','This selfcheck inspects flow/action guards statically; designer executed only the two targeted browser defect regressions, not the full independent QA suite'),
        ('Android TalkBack/OS permission/lockscreen/widget/push','No APK or real Android integration; design artifacts only'),
        ('PO final approval / independent G4/G5','Author selfcheck does not sign independent acceptance')]]
    limits.append({'control':'Optional future Penpot import/editability/restore','result':'NOT_PERFORMED_OPTIONAL','reason':'No connected workspace; updated AS-83 AC3 accepts editable SVG + generator/tokens/preview/manifest + ZIP restore. No Penpot completion claimed.'})
    report={'checked_at':now,'artifact_version':'0.1.0-review','role':'Product Designer selfcheck','result':'PASS_FOR_LISTED_LOCAL_CHECKS' if all(c['result']=='PASS' for c in checks) else 'FAIL','checks':checks,'contrast':contrast,'limitations':limits}
    dump(EVIDENCE/'selfcheck.json',report)
    records=[]
    for p in sorted(ROOT.rglob('*')):
        if p.is_file() and p.name!='manifest.json' and '__pycache__' not in p.parts:
            rel=str(p.relative_to(ROOT));entry={'path':rel,'sha256':sha(p),'bytes':p.stat().st_size}
            match=re.match(r'(D\d\d)(?:-([a-z-]+))?-(light|dark)\.svg',p.name)
            if p.parent.name=='screens' and match:entry.update(screen_id=match.group(1),state=match.group(2) or 'default',theme=match.group(3),source='sources/build.py + tokens/semantic.json + sources/fixtures.json + sources/state-map.json',editable=True,data_classification='synthetic')
            records.append(entry)
    dump(ROOT/'sources/manifest.json',{'version':'0.1.0-review','jira':'AS-83','direction':'A — Тихий рабочий стол','selection':'Coordinator selected reversible MVP; final PO acceptance PENDING','source_of_truth':'Versioned JSON tokens + review export version; current local source, future private Git handoff','editable_originals':['sources/build.py','screens/*.svg','tokens/semantic.json','preview/*'],'penpot_workspace':None,'penpot_status':'NOT_PERFORMED_OPTIONAL: no connected workspace; updated AS-83 AC3 accepts the SVG source bundle; no .penpot/.fig claimed','approved_export_version':None,'review_export_version':'0.1.0-review','git_head_sha':None,'g4':'PENDING','g5':'PENDING','manifest_hash_rule':'Manifest excludes its own hash to avoid self-reference; all other delivered files enumerated','files':records})
    print(json.dumps({'result':report['result'],'checks':len(checks),'failed':[c['check'] for c in checks if c['result']=='FAIL'],'contrast_pairs':len(contrast),'svg_files':len(svgs),'restored_files':len(recovered),'pending':[c['control'] for c in limits if c['result']=='PENDING']},ensure_ascii=False))
    return 0 if all(c['result']=='PASS' for c in checks) else 1


if __name__=='__main__':raise SystemExit(main())
