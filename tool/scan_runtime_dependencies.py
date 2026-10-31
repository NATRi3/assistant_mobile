#!/usr/bin/env python3
"""OSV scan of frozen APK runtime + hosted Pub metadata only.
This does not assert build-tool or device security acceptance. Public coordinates
and versions are the only data disclosed to OSV; source and tokens are not sent.
"""
import datetime,json,pathlib,re,urllib.request
root=pathlib.Path(__file__).resolve().parents[1]
queries=[]
for line in (root/'android/app/gradle-arm64.lockfile').read_text().splitlines():
    if '=' not in line or line.startswith('#'):continue
    coordinate,configs=line.split('=',1)
    if 'debugRuntimeClasspath' not in configs.split(',') or coordinate.count(':')!=2:continue
    group,name,version=coordinate.split(':')
    queries.append({'package':{'name':group+':'+name,'ecosystem':'Maven'},'version':version})
# Parse the fixed Pub lock package entries without adding a parser dependency.
packages={};name=None
for line in (root/'pubspec.lock').read_text().splitlines():
    match=re.fullmatch(r'  ([A-Za-z0-9_]+):',line)
    if match:name=match.group(1);packages[name]={}
    match=re.fullmatch(r'    (source|version): (.+)',line)
    if match and name:packages[name][match.group(1)]=match.group(2).strip('"\'')
for name,p in packages.items():
    if p.get('source')=='hosted':queries.append({'package':{'name':name,'ecosystem':'Pub'},'version':p['version']})
results=[]
for start in range(0,len(queries),100):
    request=urllib.request.Request('https://api.osv.dev/v1/querybatch',data=json.dumps({'queries':queries[start:start+100]}).encode(),headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(request,timeout=60) as response:results.extend(json.load(response)['results'])
assert len(queries)==len(results)
report={'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'ARM64 debug runtime and hosted Pub; build tooling assessed separately','queries':queries,'results':results}
out=root/'build/evidence';out.mkdir(parents=True,exist_ok=True)
(out/'runtime-vulnerabilities.json').write_text(json.dumps(report,indent=2)+'\n')
findings=[(q,v) for q,v in zip(queries,results) if v.get('vulns')]
print(json.dumps({'packages':len(queries),'findings':findings},indent=2))
if findings:raise SystemExit(1)
