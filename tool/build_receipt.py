#!/usr/bin/env python3
"""Record development APK provenance without secrets or machine environment."""
import hashlib,json,pathlib,subprocess,sys,zipfile
root=pathlib.Path(__file__).resolve().parents[1]
apk=pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else root/'build/app/outputs/flutter-apk/app-debug.apk'
out=root/'build/evidence';out.mkdir(parents=True,exist_ok=True)
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def git(*args):return subprocess.check_output(['git',*args],cwd=root,text=True).strip()
with zipfile.ZipFile(apk) as z:
 names=z.namelist();dex=[n for n in names if n.endswith('.dex')];abis=sorted({n.split('/')[1] for n in names if n.startswith('lib/') and n.endswith('.so')})
 assert 'AndroidManifest.xml' in names and dex and 'arm64-v8a' in abis
 locks=[p for p in root.rglob('*lockfile') if 'build' not in p.parts and '.dart_tool' not in p.parts]
 locks += [root/'pubspec.lock',root/'android/gradle/verification-metadata.xml',root/'tool/toolchain.lock.json']
 receipt={'kind':'debug-signed development evidence; NOT owner release','source_head':git('rev-parse','HEAD'),'dirty':bool(git('status','--porcelain')),'apk_sha256':digest(apk),'apk_bytes':apk.stat().st_size,'abis':abis,'dex':dex,'locked_inputs':{str(p.relative_to(root)):digest(p) for p in locks},'runtime_evidence':'PENDING: real auth/Keystore lifecycle, TLS origin, S25, Firebase, release signing'}
(out/'build-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt,indent=2))
