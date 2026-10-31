#!/usr/bin/env bash
# Disposable API36/KVM native execution. No owner data, transport fallback or auth bypass.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
evidence="$root/build/evidence/native-instrumentation"
results="$root/build/app/outputs/androidTest-results/connected/debug"
mkdir -p "$evidence"
# Freshness: only this dedicated connected-debug output is removed.
rm -rf -- "$results"
export AS91_STARTED_AT="$(date +%s)" AS91_PHASE=preflight AS91_GRADLE_STATUS=NOT_RUN AS91_PARSER_STATUS=NOT_RUN
export AS91_RESULTS="$results" AS91_EVIDENCE="$evidence"
export AS91_BOOT_SECONDS=0 AS91_INSTALL_SECONDS=0 AS91_SUITE_SECONDS=0
export AS91_DISK_BEFORE="$(df --output=avail -B1 "$root" | tail -1 | tr -d ' ')"
emulator_pid=''
avd_root=''
serial=emulator-5554
export ANDROID_SERIAL="$serial" ADB_SERVER_SOCKET="tcp:localhost:5038" ANDROID_ADB_SERVER_PORT=5038
export AS91_EMULATOR_STARTED=false AS91_DISK_AFTER_INSTALL=0
receipt() {
 AS91_EXIT_STATUS="$1" python3 - <<'PY'
import hashlib,json,os,pathlib,platform,re,subprocess,zipfile
root=pathlib.Path.cwd(); out=pathlib.Path(os.environ['AS91_EVIDENCE'])
def command(args,limit=512):
 try:return subprocess.check_output(args,stderr=subprocess.DEVNULL,timeout=5,text=True).strip()[:limit]
 except (OSError,subprocess.SubprocessError):return 'UNAVAILABLE'
event={}
try:event=json.loads(pathlib.Path(os.environ.get('GITHUB_EVENT_PATH','/nonexistent')).read_text())
except (OSError,ValueError):pass
pr=event.get('pull_request',{})
receipt={'phase':os.environ['AS91_PHASE'],'exit_status':int(os.environ['AS91_EXIT_STATUS']),
 'gradle_exit_status':os.environ['AS91_GRADLE_STATUS'],'accounting_exit_status':os.environ['AS91_PARSER_STATUS'],
 'source_head':command(['git','rev-parse','HEAD']),'source_dirty':bool(command(['git','status','--porcelain','--untracked-files=no'])),'source_tree':command(['git','rev-parse','HEAD^{tree}']),
 'pr_head':pr.get('head',{}).get('sha'),'pr_base':pr.get('base',{}).get('sha'),
 'tested_merge_sha':os.environ.get('GITHUB_SHA') if pr else None,'github_sha':os.environ.get('GITHUB_SHA'),
 'run_url':os.environ.get('GITHUB_SERVER_URL','https://github.com')+'/'+os.environ.get('GITHUB_REPOSITORY','')+'/actions/runs/'+os.environ.get('GITHUB_RUN_ID',''),
 'run_attempt':os.environ.get('GITHUB_RUN_ATTEMPT'),'ImageOS':os.environ.get('ImageOS'),'ImageVersion':os.environ.get('ImageVersion'),
 'kernel':platform.release(),'cpu_count':os.cpu_count(),'cpu_model':next((line.split(':',1)[1].strip() for line in pathlib.Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name')),platform.machine()),
 'host_memory_kib':next((int(line.split()[1]) for line in pathlib.Path('/proc/meminfo').read_text().splitlines() if line.startswith('MemTotal:')),0),
 'kvm_exists':pathlib.Path('/dev/kvm').exists(),'kvm_access':os.access('/dev/kvm',os.R_OK|os.W_OK),
 'disk_before_bytes':int(os.environ['AS91_DISK_BEFORE']),'disk_after_install_bytes':int(os.environ['AS91_DISK_AFTER_INSTALL']),'disk_final_bytes':__import__('shutil').disk_usage(root).free,
 'install_seconds':int(os.environ['AS91_INSTALL_SECONDS']),'boot_seconds':int(os.environ['AS91_BOOT_SECONDS']),'suite_seconds':int(os.environ['AS91_SUITE_SECONDS']),
 'elapsed_seconds':int(__import__('time').time())-int(os.environ['AS91_STARTED_AT']),
 'result_directory':'build/app/outputs/androidTest-results/connected/debug',
 'runtime_status':'PASS' if os.environ['AS91_EXIT_STATUS']=='0' else 'PENDING_OR_FAILED',
 'physical_device_acceptance':'PENDING','security_level_claim':'emulator metadata only; no hardware assurance'}
sdk=pathlib.Path(os.environ.get('ANDROID_HOME','/nonexistent'))
receipt['adb_version']=command([str(sdk/'platform-tools/adb'),'version'])
receipt['emulator_version']=command([str(sdk/'emulator/emulator'),'-version'])
receipt['acceleration']=command([str(sdk/'emulator/emulator'),'-accel-check'])
for key,prop in [('fingerprint','ro.build.fingerprint'),('security_patch','ro.build.version.security_patch'),('abi','ro.product.cpu.abi')]:
 receipt[key]=command([str(sdk/'platform-tools/adb'),'-s','emulator-5554','shell','getprop',prop]) if os.environ['AS91_EMULATOR_STARTED']=='true' else 'NOT_STARTED'
receipt['apks']=[]
for relative in ['build/app/outputs/apk/debug/app-debug.apk','build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk']:
 path=root/relative
 if path.exists():
  with path.open('rb') as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
  try:
   with zipfile.ZipFile(path) as apk: native_libraries=sorted(n for n in apk.namelist() if n.startswith('lib/') and n.endswith('.so'))
  except zipfile.BadZipFile:native_libraries=[]
  receipt['apks'].append({'path':relative,'sha256':digest,'bytes':path.stat().st_size,'native_libraries':native_libraries,'metadata':command([str(sdk/'cmdline-tools/pinned/bin/apkanalyzer'),'apk','summary',str(path)])})
# Read only the fixed, bounded numeric metrics file written by androidTest, never app data directories.
metrics=command([str(sdk/'platform-tools/adb'),'-s','emulator-5554','shell','run-as','io.github.natri3.assistant','cat','cache/as91-runtime-metrics.json']) if os.environ['AS91_EMULATOR_STARTED']=='true' else '{}'
try:
 values=json.loads(metrics)
 assert set(values)=={'expiry_wait_ms','ec_security_level','aes_security_level'}
 assert all(type(v) is int and -9<=v<=999999999 for v in values.values())
 assert values['expiry_wait_ms']>=305000
 receipt['auth_metrics']=values
except (ValueError,AssertionError,TypeError):receipt['auth_metrics']='PENDING'
if os.environ['AS91_EMULATOR_STARTED']=='true':
 diagnostic=command([str(sdk/'platform-tools/adb'),'-s','emulator-5554','shell','run-as','io.github.natri3.assistant','cat','cache/as91-prompt-ui.json'],4096)
 try:
  ids=json.loads(diagnostic)
  assert type(ids) is list and len(ids)<=32
  assert all(type(v) is str and re.fullmatch(r'com\.android\.(settings|systemui):id/[A-Za-z0-9_]{1,80}',v) for v in ids)
  receipt['unrecognized_prompt_system_resource_ids']=ids
 except (ValueError,AssertionError,TypeError):pass
if receipt['exit_status']==0 and (receipt['auth_metrics']=='PENDING' or len(receipt['apks'])!=2 or any(apk['metadata']=='UNAVAILABLE' for apk in receipt['apks']) or any(receipt[key]=='UNAVAILABLE' for key in ['fingerprint','security_patch','abi'])):
 receipt['exit_status']=1;receipt['phase']='EVIDENCE_INCOMPLETE';receipt['runtime_status']='PENDING_OR_FAILED'
(out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
raise SystemExit(0 if receipt['exit_status']==0 else 1)
PY
}
finish() {
 local exit_status=$?
 trap - EXIT INT TERM
 set +e
 python3 tool/check_instrumentation_results.py "$results" --output "$evidence" --started-at "$AS91_STARTED_AT"
 export AS91_PARSER_STATUS=$?
 if [[ "$exit_status" == 0 && "$AS91_PARSER_STATUS" != 0 ]]; then exit_status=1; fi
 receipt "$exit_status" || exit_status=1
 # Shut down only the PID and AVD created here. Never touch other transports.
 if [[ -n "$emulator_pid" ]]; then
  timeout 5s "$ANDROID_HOME/platform-tools/adb" -s "$serial" emu kill >/dev/null 2>&1
  kill "$emulator_pid" >/dev/null 2>&1
  for ((attempt=0; attempt<10; attempt++)); do kill -0 "$emulator_pid" 2>/dev/null || break; sleep 1; done
  kill -KILL "$emulator_pid" >/dev/null 2>&1
  wait "$emulator_pid" >/dev/null 2>&1
 fi
 if [[ -n "$avd_root" ]]; then rm -rf -- "$avd_root"; fi
 # These artifacts contain only seven result identities/statuses and bounded receipts.
 local bytes
 bytes=$(du -sb "$evidence" | cut -f1)
 if (( bytes > 20 * 1024 * 1024 )); then exit_status=1; fi
 exit "$exit_status"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
: "${RUNNER_TEMP:?}" "${ANDROID_HOME:?}"
[[ "$ANDROID_HOME" == "$RUNNER_TEMP/assistant-toolchains/android" ]]
python3 -m unittest tool/test_check_instrumentation_results.py
python3 - <<'APK'
import zipfile
with zipfile.ZipFile('build/app/outputs/apk/debug/app-debug.apk') as apk:
 assert 'lib/x86_64/libflutter.so' in apk.namelist(), 'X86_64_ENGINE_MISSING'
 assert 'assets/flutter_assets/kernel_blob.bin' in apk.namelist(), 'DEBUG_KERNEL_MISSING'
with zipfile.ZipFile('build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk') as apk:
 assert 'AndroidManifest.xml' in apk.namelist(), 'TEST_APK_MISSING'
APK
(( AS91_DISK_BEFORE >= 6 * 1024 * 1024 * 1024 ))
[[ -e /dev/kvm ]]
if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
 # GitHub's documented rule, only on this ephemeral hosted runner.
 [[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]]
 echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules >/dev/null
 sudo udevadm control --reload-rules
 sudo udevadm trigger --name-match=kvm
fi
[[ -r /dev/kvm && -w /dev/kvm ]]
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/pinned/bin:$PATH"
# Refuse even an offline/unavailable physical transport; the ADB server is job-local.
adb start-server >/dev/null
[[ -z "$(adb devices | tail -n +2 | tr -d '[:space:]')" ]]
export AS91_PHASE=runtime_install
start=$(date +%s)
timeout --signal=TERM --kill-after=10s 240s bash tool/bootstrap_android_emulator.sh
export AS91_INSTALL_SECONDS=$(( $(date +%s) - start ))
export AS91_DISK_AFTER_INSTALL="$(df --output=avail -B1 "$root" | tail -1 | tr -d ' ')"
emulator -accel-check >/dev/null
export AS91_PHASE=avd_boot
avd_root=$(mktemp -d "$RUNNER_TEMP/as91-avd-XXXXXX")
export ANDROID_AVD_HOME="$avd_root"
printf 'no\n' | avdmanager create avd --name as91-api36 --package 'system-images;android-36;default;x86_64' --path "$avd_root/as91-api36.avd" >/dev/null
cat >> "$avd_root/as91-api36.avd/config.ini" <<'AVD'
hw.lcd.width=720
hw.lcd.height=1280
hw.lcd.density=320
hw.cpu.ncore=2
hw.ramSize=2048
disk.dataPartition.size=2G
AVD
start=$(date +%s)
# Raw emulator diagnostics remain temporary and are never uploaded.
emulator -avd as91-api36 -port 5554 -no-window -no-audio -no-boot-anim -no-snapshot -wipe-data -accel on -gpu swiftshader -cores 2 -memory 2048 -prop persist.sys.locale=en-US > "$avd_root/emulator.log" 2>&1 &
emulator_pid=$!
export AS91_EMULATOR_STARTED=true
ready=false
while (( $(date +%s) - start < 180 )); do
 kill -0 "$emulator_pid"
 if [[ "$(timeout 5s adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] && timeout 5s adb -s "$serial" shell pm path android 2>/dev/null | grep -q '^package:'; then ready=true; break; fi
 sleep 2
done
[[ "$ready" == true ]]
export AS91_BOOT_SECONDS=$(( $(date +%s) - start ))
[[ "$(adb devices | tail -n +2 | sed '/^$/d' | awk '{print $1}')" == "$serial" ]]
export AS91_PHASE=synthetic_setup
adb -s "$serial" shell svc wifi disable
adb -s "$serial" shell svc data disable
adb -s "$serial" shell settings put system screen_off_timeout 900000
adb -s "$serial" shell svc power stayon true
# Provisioning only; the observed androidTest system UI owns any initial OS unlock.
# Initial setup is never counted as completion of an app/native credential prompt.
adb -s "$serial" shell locksettings set-pin 864209 >/dev/null
export AS91_PHASE=native_suite
start=$(date +%s)
set +e
(cd android && timeout --signal=TERM --kill-after=10s 540s ./gradlew --no-daemon --max-workers=2 --dependency-verification strict :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=io.github.natri3.assistant.security.DeviceSecurityTest,io.github.natri3.assistant.security.DomainCacheSecurityTest,io.github.natri3.assistant.security.NativeLifecycleVaultTest -Pandroid.testInstrumentationRunnerArguments.synthetic_emulator=true)
export AS91_GRADLE_STATUS=$?
set -e
export AS91_SUITE_SECONDS=$(( $(date +%s) - start ))
export AS91_PHASE=result_accounting
exit "$AS91_GRADLE_STATUS"
