#!/usr/bin/env bash
# Install only the three reviewed official runtime inputs into the isolated CI SDK.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${RUNNER_TEMP:?Ephemeral runner directory required}" "${ANDROID_HOME:?Isolated SDK required}"
[[ "$ANDROID_HOME" == "$RUNNER_TEMP/assistant-toolchains/android" ]]
read_pin() { python3 -c 'import json,sys;v=json.load(open("tool/toolchain.lock.json"))["android"]; print(v[sys.argv[1]][sys.argv[2]])' "$1" "$2"; }
install_pin() {
 local component="$1" destination="$2" archive final_url
 archive=$(mktemp "$RUNNER_TEMP/as91-runtime-XXXXXX.zip")
 # One bounded transfer; no silently floating sdkmanager package or runtime retry.
 final_url=$(curl --proto '=https' --proto-redir '=https' --tlsv1.2 --fail --silent --show-error --location --connect-timeout 15 --max-time 180 --output "$archive" --write-out '%{url_effective}' "$(read_pin "$component" url)")
 [[ "$final_url" == "$(read_pin "$component" url)" ]]
 [[ "$(stat -c %s "$archive")" == "$(read_pin "$component" size)" ]]
 printf '%s  %s\n' "$(read_pin "$component" sha1)" "$archive" | sha1sum --check --status
 printf '%s  %s\n' "$(read_pin "$component" sha256)" "$archive" | sha256sum --check --status
 mkdir -p "$destination"
 unzip -q "$archive" -d "$destination"
 # Remove only this already verified archive, never SDK/host caches.
 rm -- "$archive"
}
case "${1:-}" in
 --platform-tools-only)
  [[ ! -e "$ANDROID_HOME/platform-tools" ]]
  install_pin platform_tools "$ANDROID_HOME"
  grep -Eq '^Pkg.Revision *= *37\.0\.1$' "$ANDROID_HOME/platform-tools/source.properties"
  ;;
 "")
  [[ ! -e "$ANDROID_HOME/emulator" && ! -e "$ANDROID_HOME/system-images/android-36/default/x86_64" ]]
  install_pin emulator "$ANDROID_HOME"
  install_pin system_image "$ANDROID_HOME/system-images/android-36/default"
  grep -Eq '^Pkg.Revision *= *37\.2\.13$' "$ANDROID_HOME/emulator/source.properties"
  grep -Eq '^Pkg.Revision *= *2$' "$ANDROID_HOME/system-images/android-36/default/x86_64/source.properties"
  ;;
 *) exit 2 ;;
esac
