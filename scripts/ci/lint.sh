#!/usr/bin/env bash
# SwiftLint over App, Packages/VoyagerKit/Sources and UITests (.swiftlint.yml). Warnings fail.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
swiftlint version
swiftlint lint --strict --quiet --config .swiftlint.yml
