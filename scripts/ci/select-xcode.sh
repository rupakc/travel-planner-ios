#!/usr/bin/env bash
# Select the pinned Xcode (XCODE_VERSION, set in ios-ci.yml) on the macOS runner.
set -euo pipefail

: "${XCODE_VERSION:?XCODE_VERSION is not set}"
APP="/Applications/Xcode_${XCODE_VERSION}.app"

if [[ ! -d "$APP" ]]; then
  echo "select-xcode: $APP is not installed. Installed:" >&2
  ls -d /Applications/Xcode*.app >&2 || true
  echo "Fix XCODE_VERSION in .github/workflows/ios-ci.yml to an installed Xcode >= 26.0 released at least 14 days ago." >&2
  exit 1
fi

sudo xcode-select -s "$APP"
xcodebuild -version
