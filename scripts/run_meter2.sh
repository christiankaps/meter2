#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="/private/tmp/meter2-derived-data"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/Meter2.app"

cd "$ROOT_DIR"

xcodebuild \
  -project Meter2.xcodeproj \
  -scheme Meter2 \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

open "$APP_PATH"
