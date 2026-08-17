#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STANDARDS_ROOT="${STANDARDS_ROOT:-/Users/crp/Projects/Codex 开发规范}"
TARGET_VERSION="${TARGET_VERSION:?TARGET_VERSION is required}"
TARGET_BUILD="${TARGET_BUILD:?TARGET_BUILD is required}"

cd "$ROOT"
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || {
    echo "error: prepare-formal-release requires a clean worktree" >&2
    exit 1
}
python3 "$STANDARDS_ROOT/scripts/formal_release_git.py" preflight --path "$ROOT"
python3 scripts/release_tool.py prepare --version "$TARGET_VERSION" --build "$TARGET_BUILD"
python3 scripts/release_tool.py version-check --release
echo "Prepared formal release metadata. Commit only the version and changelog changes."
