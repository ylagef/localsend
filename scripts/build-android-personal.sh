#!/usr/bin/env bash
# Run through heavy's gradle class on GEEKOM. Signing material stays on that host.
set -euo pipefail
if [[ "$(uname -s)" != Linux ]]; then
  echo 'Android builds must run on GEEKOM, not the Mac.' >&2
  exit 1
fi
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${FLUTTER_ROOT:?Set FLUTTER_ROOT to the pinned Linux Flutter installation}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export LOCALSEND_ANDROID_KEY_PROPERTIES="${LOCALSEND_ANDROID_KEY_PROPERTIES:-$HOME/.local/share/localsend-personal/android/key.properties}"
export PATH="$FLUTTER_ROOT/bin:$HOME/.cargo/bin:$PATH"
[[ -f "$LOCALSEND_ANDROID_KEY_PROPERTIES" ]] || { echo 'Missing personal Android signing configuration.' >&2; exit 1; }
[[ -n "${LOCALSEND_ANDROID_BUILD_NUMBER:-}" ]] || { echo 'Set LOCALSEND_ANDROID_BUILD_NUMBER to a unique increasing value (split ABI codes multiply it by ten).' >&2; exit 1; }
cd "$project_root"
artifact="artifacts/LocalSend-Personal-android-arm64.apk"
[[ ! -e "$artifact" ]] || { echo "Preserve the existing $artifact before building another delivery." >&2; exit 1; }
python3 - <<'PY'
import json, os, subprocess
expected = json.load(open('.fvmrc'))['flutter']
actual = json.loads(subprocess.check_output(['flutter', '--version', '--machine']))['frameworkVersion']
if actual != expected:
    raise SystemExit(f'Flutter {actual} differs from pinned {expected}')
number = int(os.environ['LOCALSEND_ANDROID_BUILD_NUMBER'])
if not 0 < number <= 214748364:
    raise SystemExit('Build number exceeds Android split ABI versionCode range')
PY
fork_version="$(python3 -c 'import json; print(json.load(open("fork-version.json"))["version"])')"
cd app
flutter pub get --enforce-lockfile
flutter build apk --release --split-per-abi --target-platform android-arm64 \
  --build-name "$fork_version" --build-number "$LOCALSEND_ANDROID_BUILD_NUMBER"
cd "$project_root"
mkdir -p artifacts
candidate="$artifact.pending-$$"
cp app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$candidate"
build_tools="$ANDROID_HOME/build-tools/36.0.0"
"$build_tools/apksigner" verify --verbose --print-certs "$candidate" > "$candidate.certificate.txt"
"$build_tools/aapt2" dump badging "$candidate" > "$candidate.package.txt"
python3 scripts/verify-android-personal.py "$candidate" "$fork_version" "$LOCALSEND_ANDROID_BUILD_NUMBER"
# Atomic exclusive publication to the local delivery path; retain failed candidates for diagnosis.
python3 - "$candidate" "$artifact" <<'PYVERIFY'
import os, sys
source, destination = sys.argv[1:]
os.link(source, destination)
os.unlink(source)
for suffix in ('.certificate.txt', '.package.txt'):
    os.replace(source + suffix, destination + suffix)
PYVERIFY
sha256sum "$artifact" > "$artifact.sha256"
echo "Verified APK: $project_root/$artifact"
