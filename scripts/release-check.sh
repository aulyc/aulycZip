#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/standards-dependency.sh"
require_standards_root \
    standards/version.json \
    scripts/standards_check.py
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:?DEVELOPER_ID_APPLICATION is required}"
cd "$ROOT"

[[ -z "$(git status --porcelain --untracked-files=all)" ]] || {
    echo "error: release-check requires a clean worktree" >&2
    exit 1
}
python3 "$STANDARDS_ROOT/scripts/standards_check.py" project --path "$ROOT" --strict
python3 scripts/release_tool.py version-check --release
bash scripts/compile-check.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Config/Info.plist)"
CANDIDATE_ROOT="$ROOT/.cache/release-candidate"
AULYCZIP_APP_OUTPUT_DIR="$CANDIDATE_ROOT" \
AULYCZIP_RELEASE_CHANNEL=candidate \
AULYCZIP_RELEASE_TAG="$VERSION" \
SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
    bash scripts/bundle.sh --release
python3 scripts/release_tool.py verify-candidate \
    --app "$CANDIDATE_ROOT/aulycZip.app"
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || {
    echo "error: release-check changed the source worktree" >&2
    exit 1
}
echo "Formal release candidate passed"
