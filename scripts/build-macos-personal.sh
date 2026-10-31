#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/personal-env.sh"
cd "$PERSONAL_PROJECT_ROOT"

# This adapter is called inside heavy's xcodebuild admission, including from release-tools.
if [[ "${LOCALSEND_ADMITTED_BUILD:-}" != 1 ]]; then
  exec heavy run --class xcodebuild --label 'LocalSend Personal macOS' -- bash -c 'export LOCALSEND_ADMITTED_BUILD=1; exec bash scripts/build-macos-personal.sh'
fi

destination="$PERSONAL_PROJECT_ROOT/artifacts/LocalSend Personal.app"
if [[ -e "$destination" ]]; then
  echo 'Preserve the previous artifacts/LocalSend Personal.app before building again.' >&2
  exit 1
fi
mkdir -p artifacts
flutter pub get --enforce-lockfile
(
  cd app
  flutter build macos --release --config-only --build-number 2026103103
)
xcodebuild -workspace app/macos/Runner.xcworkspace -scheme Runner -configuration Release \
  -derivedDataPath app/build/macos-personal -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES MACOSX_DEPLOYMENT_TARGET=12.0 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=
ditto 'app/build/macos-personal/Build/Products/Release/LocalSend Personal.app' "$destination"
python3 scripts/sign-personal.py "$destination"
codesign --verify --deep --strict "$destination"
python3 scripts/record-personal-build.py "$destination"
