#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/standards-dependency.sh"
require_standards_root \
    standards/version.json \
    scripts/formal_release_git.py \
    scripts/standards_check.py
TARGET_VERSION="${TARGET_VERSION:?TARGET_VERSION is required}"
TARGET_BUILD="${TARGET_BUILD:?TARGET_BUILD is required}"

cd "$ROOT"
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || {
    echo "error: prepare-formal-release requires a clean worktree" >&2
    exit 1
}
python3 "$STANDARDS_ROOT/scripts/standards_check.py" project --path "$ROOT" --strict
python3 "$STANDARDS_ROOT/scripts/formal_release_git.py" preflight --path "$ROOT"
python3 scripts/release_tool.py prepare --version "$TARGET_VERSION" --build "$TARGET_BUILD"
python3 scripts/release_tool.py version-check --release
echo "Prepared formal release metadata. Commit only the version and changelog changes."
