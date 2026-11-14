#!/usr/bin/env bash
# Build the app for the simulator in Release (unsigned), pointing at production, and zip it to
# build/Voyager-sim-prod.zip. Debug stays on http://127.0.0.1:8001 (scripts/ci/build-sim.sh).
# The base URL and trusted hosts are set explicitly (they also live in Config/Release.xcconfig) so the
# artifact cannot drift; they reach the app through Info.plist (VoyagerBaseURL, VoyagerTrustedHosts).
# Needs scripts/ci/generate.sh first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
derived="$ROOT/build/DerivedData-sim-prod"
prod_url="https://35-207-18-35.sslip.io"
prod_host="35-207-18-35.sslip.io"

xcodebuild build \
  -project Voyager.xcodeproj \
  -scheme Voyager \
  -configuration Release \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived" \
  -clonedSourcePackagesDirPath "$ROOT/build/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipMacroValidation \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  "VOYAGER_PROD_BASE_URL=$prod_url" \
  "VOYAGER_TRUSTED_HOSTS=$prod_host"

app="$derived/Build/Products/Release-iphonesimulator/Voyager.app"
[[ -d "$app" ]] || { echo "build-sim-prod: $app was not produced" >&2; exit 1; }
plist="$app/Info.plist"
if [[ -f "$plist" ]] && command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
  got="$(/usr/libexec/PlistBuddy -c 'Print :VoyagerBaseURL' "$plist")"
  [[ "$got" == "$prod_url" ]] || { echo "build-sim-prod: VoyagerBaseURL is '$got', expected $prod_url" >&2; exit 1; }
fi
rm -f "$ROOT/build/Voyager-sim-prod.zip"
ditto -c -k --keepParent "$app" "$ROOT/build/Voyager-sim-prod.zip"
echo "build-sim-prod: build/Voyager-sim-prod.zip"
