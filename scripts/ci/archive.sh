#!/usr/bin/env bash
# Archive the app for devices (Release, unsigned): proves the device build compiles.
# Signing and TestFlight come with Task 49. Needs scripts/ci/generate.sh first.
#
# VOYAGER_PROD_BASE_URL / VOYAGER_TRUSTED_HOSTS from the environment (the repo variables)
# override Config/Release.xcconfig only when non-empty.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

overrides=()
[[ -n "${VOYAGER_PROD_BASE_URL:-}" ]] && overrides+=("VOYAGER_PROD_BASE_URL=${VOYAGER_PROD_BASE_URL}")
[[ -n "${VOYAGER_TRUSTED_HOSTS:-}" ]] && overrides+=("VOYAGER_TRUSTED_HOSTS=${VOYAGER_TRUSTED_HOSTS}")

xcodebuild archive \
  -project Voyager.xcodeproj \
  -scheme Voyager \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ROOT/build/Voyager.xcarchive" \
  -derivedDataPath "$ROOT/build/DerivedData-archive" \
  -clonedSourcePackagesDirPath "$ROOT/build/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  ${overrides[@]+"${overrides[@]}"}

echo "archive: build/Voyager.xcarchive"
