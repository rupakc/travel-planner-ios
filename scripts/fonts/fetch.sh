#!/usr/bin/env bash
# Download the bundled fonts (Inter, Sora; SIL OFL) pinned in tools.lock, check each
# download's SHA-256 and copy the files into Packages/VoyagerKit/Sources/DesignSystem/Resources/Fonts/.
#
# tools.lock lines:  font:<FileName> <version> <url> <sha256> [path inside the zip]
#   font:Inter-Regular.ttf 4.1 https://…/Inter-4.1.zip <sha256> extras/ttf/Inter-Regular.ttf
#   font:OFL.txt 4.1 https://…/OFL.txt <sha256>
# A URL ending in .zip is extracted (member required); anything else is copied as is.
# The fonts are committed; re-run this only to change a pin.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK="${TOOLS_LOCK:-$ROOT/tools.lock}"
DEST="${FONTS_DIR:-$ROOT/Packages/VoyagerKit/Sources/DesignSystem/Resources/Fonts}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

count=0
while read -r name version url sum member; do
  file="${name#font:}"
  download="$WORK/$(printf '%s' "$url" | shasum -a 256 | cut -c1-16)"
  if [[ ! -f "$download" ]]; then
    curl -fsSL --retry 3 -o "$download" "$url"
  fi
  actual="$(shasum -a 256 "$download" | awk '{print $1}')"
  if [[ "$actual" != "$sum" ]]; then
    echo "fetch: SHA-256 mismatch for $file ($version, $url): expected $sum, got $actual" >&2
    exit 1
  fi
  mkdir -p "$DEST"
  if [[ "$url" == *.zip ]]; then
    [[ -n "$member" ]] || { echo "fetch: $file comes from a zip; give the member path" >&2; exit 1; }
    unzip -p "$download" "$member" > "$DEST/$file"
    [[ -s "$DEST/$file" ]] || { echo "fetch: $member not found in $url" >&2; exit 1; }
  else
    cp "$download" "$DEST/$file"
  fi
  echo "fetch: $file ($version)"
  count=$((count + 1))
done < <(grep -E '^font:' "$LOCK" || true)

if [[ $count -eq 0 ]]; then
  echo "fetch: no font:* pins in $(basename "$LOCK"); nothing to do"
fi
