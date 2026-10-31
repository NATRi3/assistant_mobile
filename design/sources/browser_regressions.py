#!/usr/bin/env python3
"""Designer regression checks for QA defects only; not independent functional QA."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import functools
import hashlib
import http.server
import json
import threading
from playwright.sync_api import sync_playwright, expect

ROOT=Path(__file__).resolve().parents[1]


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--phase',choices=['red','green'],required=True);args=parser.parse_args()
    out=ROOT/'evidence';out.mkdir(exist_ok=True)
    sources={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in ['preview/review.js','preview/layout.css','preview/review.css']}
    results=[];errors=[];blocked=[];layouts=[]
    class Handler(http.server.SimpleHTTPRequestHandler):
        def log_message(self,*_):pass
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Handler,directory=str(ROOT)))
    threading.Thread(target=server.serve_forever,daemon=True).start()
    base=f'http://127.0.0.1:{server.server_port}'
    with sync_playwright() as pw:
        browser=pw.chromium.launch(headless=True,args=['--disable-background-networking'])
        context=browser.new_context(viewport={'width':360,'height':915},reduced_motion='reduce')
        def guard(route):
            if route.request.url.startswith(base+'/'):route.continue_()
            else:blocked.append(route.request.url);route.abort()
        context.route('**/*',guard)
        page=context.new_page();page.on('pageerror',lambda e:errors.append(str(e)))
        page.goto(base+'/preview/index.html')
        def check(name,fn):
            try:fn();results.append({'check':name,'result':'PASS'})
            except Exception as exc:
                results.append({'check':name,'result':'FAIL','error':str(exc)})
                if page.locator('#confirm').is_visible():page.keyboard.press('Escape')
            print(json.dumps(results[-1],ensure_ascii=False),flush=True)
        def permission():
            for dismissal in ['cancel-button','escape']:
                page.locator('#reset').click();page.locator('#screen').select_option('D07')
                toggle=page.locator('[data-toggle="notifications"]')
                expect(toggle).not_to_be_checked();toggle.check();expect(page.locator('#confirm')).to_be_visible()
                if dismissal=='cancel-button':page.get_by_role('button',name='Отмена',exact=True).click()
                else:page.keyboard.press('Escape')
                expect(page.locator('#confirm')).not_to_be_visible()
                expect(toggle).not_to_be_checked(timeout=500)
                expect(page.locator('#announcement')).not_to_contain_text('Opt-in изменён')
                page.locator('#screen').select_option('D02');page.locator('#screen').select_option('D07')
                expect(page.locator('[data-toggle="notifications"]')).not_to_be_checked()
            # The fix must not disable the positive confirmation path.
            page.locator('[data-toggle="notifications"]').check();page.locator('#confirm-go').click()
            expect(page.locator('[data-toggle="notifications"]')).to_be_checked()
            page.locator('#screen').select_option('D02');page.locator('#screen').select_option('D07')
            expect(page.locator('[data-toggle="notifications"]')).to_be_checked()
        check('Permission cancel/Escape leaves visual and persisted demo state unchecked; confirm still works',permission)
        def navigation():
            page.locator('#reset').click()
            for width in [360,412,480]:
                page.set_viewport_size({'width':width,'height':915})
                for scale in ['1','2']:
                    page.locator('#scale').select_option(scale)
                    for theme in ['light','dark']:
                        page.locator('#theme').select_option(theme);page.locator('#screen').select_option('D02')
                        bounds=page.locator('.tabs button').evaluate_all('''els=>els.map(e=>{const b=e.getBoundingClientRect(),range=document.createRange();range.selectNodeContents(e);const t=range.getBoundingClientRect();return {label:e.textContent,button:{left:b.left,right:b.right,top:b.top,bottom:b.bottom,height:b.height},glyph:{left:t.left,right:t.right,top:t.top,bottom:t.bottom},fits:t.left>=b.left-.25&&t.right<=b.right+.25&&t.top>=b.top-.25&&t.bottom<=b.bottom+.25}})''')
                        font=page.locator('.tabs button').first.evaluate('(e)=>getComputedStyle(e).fontSize')
                        a,b=bounds;overlap=min(a['glyph']['right'],b['glyph']['right'])>max(a['glyph']['left'],b['glyph']['left']) and min(a['glyph']['bottom'],b['glyph']['bottom'])>max(a['glyph']['top'],b['glyph']['top'])
                        layouts.append({'width':width,'scale':scale,'theme':theme,'font_size':font,'bounds':bounds,'overlap':overlap})
                        if width==360 and scale=='2' and theme=='light':page.locator('.tabs').screenshot(path=str(out/f'navigation-{args.phase}-200-360.png'))
                        assert all(x['fits'] and x['button']['height']>=48 for x in bounds) and not overlap,bounds
                        assert font==('32px' if scale=='2' else '16px'),font
                        page.locator('.tabs [data-route="D03"]').click();expect(page.locator('#screen')).to_have_value('D03')
                        page.locator('.tabs [data-route="D02"]').click();expect(page.locator('#screen')).to_have_value('D02')
        check('Navigation glyphs fit clickable bounds without overlap at 100/200%, both themes, 360/412/480px',navigation)
        report={'checked_at':datetime.now(timezone.utc).isoformat(),'role':'Designer targeted regression; not independent QA/G5','phase':args.phase,'result':'PASS' if all(x['result']=='PASS' for x in results) and not errors and not blocked else 'FAIL','chromium':browser.version,'checks':results,'layout_cases':layouts,'source_sha256':sources,'source_unchanged_during_run':all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in sources.items()),'page_errors':errors,'external_requests_blocked':blocked}
        (out/f'browser-regressions-{args.phase}.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
        browser.close()
    server.shutdown()
    print(json.dumps({'phase':args.phase,'result':report['result'],'checks':len(results),'layout_cases':len(layouts),'page_errors':errors,'external_requests_blocked':blocked}))
    return 0 if report['result']=='PASS' else 1


if __name__=='__main__':raise SystemExit(main())
