#!/usr/bin/env bash
# Build Centik.app. The first run resolves Swift packages and needs a network connection.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" ]] && [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  if ! xcodebuild -version >/dev/null 2>&1; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  fi
fi

xcodebuild \
  -project Centik.xcodeproj \
  -scheme Centik \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath build \
  build

echo
echo "Built: build/Build/Products/Debug/Centik.app"
echo "Run:   open build/Build/Products/Debug/Centik.app"
