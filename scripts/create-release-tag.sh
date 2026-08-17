#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || {
    echo "error: release tag requires a clean worktree" >&2
    exit 1
}
python3 scripts/release_tool.py version-check --release
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Config/Info.plist)"
COMMIT="$(git rev-parse HEAD)"

if git show-ref --verify --quiet "refs/tags/$VERSION"; then
    git rev-parse --verify "refs/tags/$VERSION^{tag}" >/dev/null
    [[ "$(git rev-list -n 1 "$VERSION")" == "$COMMIT" ]] || {
        echo "error: existing tag points to another commit" >&2
        exit 1
    }
    echo "Annotated tag already matches: $VERSION"
    exit 0
fi
git tag -a "$VERSION" -m "aulycZip $VERSION"
git rev-parse --verify "refs/tags/$VERSION^{tag}" >/dev/null
echo "Created annotated tag: $VERSION"
