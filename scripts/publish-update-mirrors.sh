#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROVENANCE="$(cd "$(dirname "${1:?usage: publish-update-mirrors.sh <provenance>}")" && pwd)/$(basename "$1")"
VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["version"])' "$PROVENANCE")"
DIST="$(dirname "$PROVENANCE")"
STAGING="$DIST/dual-mirror-$VERSION"
NOTES_ZH="$DIST/$VERSION.release-notes.zh-CN.md"
NOTES_EN="$DIST/$VERSION.release-notes.en.md"

cd "$ROOT"
python3 scripts/release_tool.py release-notes \
    --version "$VERSION" --language zh-CN --output "$NOTES_ZH"
python3 scripts/release_tool.py release-notes \
    --version "$VERSION" --language en --output "$NOTES_EN"
bash scripts/dual-mirror-release.sh prepare \
    --provenance "$PROVENANCE" \
    --notes-zh-cn "$NOTES_ZH" \
    --notes-en "$NOTES_EN" \
    --output-dir "$STAGING"
bash scripts/dual-mirror-release.sh preflight \
    --plan "$STAGING/dual-mirror-plan.json"
bash scripts/dual-mirror-release.sh publish \
    --plan "$STAGING/dual-mirror-plan.json" \
    --state "$STAGING/dual-mirror-state.json"
bash scripts/dual-mirror-release.sh verify \
    --plan "$STAGING/dual-mirror-plan.json" \
    --state "$STAGING/dual-mirror-state.json"
