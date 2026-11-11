#!/usr/bin/env bash
# Install the pinned XcodeGen and SwiftLint from tools.lock (SHA-256 checked) and put them on PATH.
#
#   scripts/ci/bootstrap.sh            # on CI: appends the bin dirs to $GITHUB_PATH
#   eval "$(scripts/ci/bootstrap.sh)"   # locally: prints `export PATH=...`
#
# Downloads are cached in ${VOYAGER_TOOLS_DIR:-~/.cache/voyager-tools}/<name>-<version>/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_DIR="${VOYAGER_TOOLS_DIR:-$HOME/.cache/voyager-tools}"
mkdir -p "$TOOLS_DIR"

sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

# install <name> <relative path of the binary inside the archive>
install_tool() {
  local name="$1" bin_rel="$2" version url sum
  read -r _ version url sum _ < <(grep -E "^${name} " "$ROOT/tools.lock") || {
    echo "bootstrap: ${name} is not pinned in tools.lock" >&2; exit 1; }
  local dir="$TOOLS_DIR/${name}-${version}"
  if [[ ! -x "$dir/$bin_rel" ]]; then
    local archive
    archive="$(mktemp "${TMPDIR:-/tmp}/${name}.XXXXXX")"
    curl -fsSL --retry 3 -o "$archive" "$url"
    local actual
    actual="$(sha256 "$archive")"
    if [[ "$actual" != "$sum" ]]; then
      echo "bootstrap: SHA-256 mismatch for ${name} ${version}: expected ${sum}, got ${actual}" >&2
      rm -f "$archive"
      exit 1
    fi
    rm -rf "$dir"
    mkdir -p "$dir"
    unzip -q "$archive" -d "$dir"
    rm -f "$archive"
    chmod +x "$dir/$bin_rel"
  fi
  local bin_dir
  bin_dir="$(dirname "$dir/$bin_rel")"
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "$bin_dir" >> "$GITHUB_PATH"
  else
    echo "export PATH=\"$bin_dir:\$PATH\""
  fi
  echo "bootstrap: ${name} ${version} -> ${bin_dir}" >&2
}

install_tool xcodegen xcodegen/bin/xcodegen
install_tool swiftlint swiftlint
