#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="/private/tmp/meter2-derived-data"

cd "$ROOT_DIR"

xcodebuild \
  -project Meter2.xcodeproj \
  -scheme Meter2 \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  test
