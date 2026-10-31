#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_cache="${RUNNER_TEMP:-$PWD/.ci-toolchains}/assistant-toolchains"
mkdir -p "$task_cache"
read_pin() { python3 -c 'import json,sys;v=json.load(open("tool/toolchain.lock.json"));keys=sys.argv[1].split(".");
for k in keys:v=v[k]
print(v)' "$1"; }
fetch() { curl --proto '=https' --tlsv1.2 --fail --location --retry 3 "$1" -o "$2"; printf '%s  %s\n' "$3" "$2" | sha256sum --check --status; }
fetch "$(read_pin jdk.url)" "$task_cache/jdk.tar.gz" "$(read_pin jdk.sha256)"
mkdir -p "$task_cache/jdk"
tar -xzf "$task_cache/jdk.tar.gz" --strip-components=1 -C "$task_cache/jdk"
export JAVA_HOME="$task_cache/jdk"
if [[ ! -d "$task_cache/flutter/.git" ]]; then git clone --no-checkout --filter=blob:none https://github.com/flutter/flutter.git "$task_cache/flutter"; fi
git -C "$task_cache/flutter" fetch origin "$(read_pin flutter.commit)"
git -C "$task_cache/flutter" checkout --detach "$(read_pin flutter.commit)"
test "$(git -C "$task_cache/flutter" rev-parse HEAD)" = "$(read_pin flutter.commit)"
fetch "$(read_pin android.cmdline_url)" "$task_cache/android.zip" "$(read_pin android.cmdline_sha256)"
mkdir -p "$task_cache/android/cmdline-tools"
unzip -q -o "$task_cache/android.zip" -d "$task_cache/unpacked"
mv "$task_cache/unpacked/cmdline-tools" "$task_cache/android/cmdline-tools/pinned"
export ANDROID_HOME="$task_cache/android" ANDROID_SDK_ROOT="$task_cache/android"
export PUB_CACHE="$task_cache/pub-cache" GRADLE_USER_HOME="$task_cache/gradle-cache"
export PATH="$JAVA_HOME/bin:$task_cache/flutter/bin:$ANDROID_HOME/cmdline-tools/pinned/bin:$ANDROID_HOME/platform-tools:$PATH"
export FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true CI=true
# License acceptance is scoped to the owner's authorized Android toolchain setup.
set +o pipefail
yes | sdkmanager --licenses >/dev/null
license_status=${PIPESTATUS[1]}
set -o pipefail
test "$license_status" -eq 0
bash tool/bootstrap_android_emulator.sh --platform-tools-only
sdkmanager 'platforms;android-36' 'build-tools;36.0.0' 'ndk;28.2.13676358' 'cmake;3.22.1'
printf '%s  %s\n' "$(read_pin android.android_jar_sha256)" "$ANDROID_HOME/platforms/android-36/android.jar" | sha256sum --check --status
flutter config --no-analytics
flutter precache --android
flutter --version --machine > "$task_cache/flutter-version.json"
python3 - "$task_cache/flutter-version.json" <<'CHECK'
import json,sys
pins=json.load(open('tool/toolchain.lock.json'));actual=json.load(open(sys.argv[1]))
assert actual['frameworkRevision']==pins['flutter']['commit']
assert actual['engineRevision']==pins['flutter']['engine']
assert actual['dartSdkVersion'].split()[0]==pins['dart']
CHECK
flutter pub get --enforce-lockfile
if [[ -n "${GITHUB_ENV:-}" ]]; then
 for name in JAVA_HOME ANDROID_HOME ANDROID_SDK_ROOT PUB_CACHE GRADLE_USER_HOME; do printf '%s=%s\n' "$name" "${!name}" >> "$GITHUB_ENV"; done
 printf '%s\n' "$JAVA_HOME/bin" "$task_cache/flutter/bin" "$ANDROID_HOME/cmdline-tools/pinned/bin" "$ANDROID_HOME/platform-tools" >> "$GITHUB_PATH"
fi
