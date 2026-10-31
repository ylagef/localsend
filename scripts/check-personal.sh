#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/personal-env.sh"
cd "$PERSONAL_PROJECT_ROOT/app"
flutter analyze
flutter test
