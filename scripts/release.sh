#!/bin/bash
# Build the DMG and publish it as a GitHub Release.
#
#   ./scripts/release.sh            # version from project.yml (MARKETING_VERSION), tag v<version>
#   ./scripts/release.sh 2.1        # explicit version
#
# Requires the GitHub CLI (`gh auth login`) and the commit you want to release pushed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' project.yml)}"
VERSION="${VERSION#v}"
TAG="v${VERSION}"
DMG="build/FreeDisplay-${VERSION}.dmg"

echo "=== Building release ${TAG} ==="
./scripts/build-dmg.sh

# Release notes: the "## v<version>" section of CHANGELOG.md (up to the next "## " heading)
NOTES="$(mktemp)"
awk -v ver="## v${VERSION}" '
  index($0, ver) == 1 { found = 1; next }
  found && /^## / { exit }
  found { print }
' CHANGELOG.md > "$NOTES"
if [ ! -s "$NOTES" ]; then
  echo "No '## v${VERSION}' section in CHANGELOG.md; using generated notes"
  NOTES_ARGS=(--generate-notes)
else
  NOTES_ARGS=(--notes-file "$NOTES")
fi

echo "=== Creating GitHub Release ${TAG} ==="
gh release create "$TAG" \
  --title "FreeDisplay ${TAG}" \
  "${NOTES_ARGS[@]}" \
  "$DMG" "$DMG.sha256"

rm -f "$NOTES"
echo "=== Release ${TAG} published ==="
