#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/standards-dependency.sh"
require_standards_root \
    standards/version.json \
    scripts/formal_release_git.py \
    scripts/standards_check.py \
    scripts/dual_mirror_release.py
PROVENANCE="$(cd "$(dirname "${1:?usage: publish-release.sh <provenance>}")" && pwd)/$(basename "$1")"
VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["version"])' "$PROVENANCE")"

cd "$ROOT"
python3 "$STANDARDS_ROOT/scripts/standards_check.py" project --path "$ROOT" --strict
python3 scripts/release_tool.py verify-provenance --provenance "$PROVENANCE"
python3 "$STANDARDS_ROOT/scripts/formal_release_git.py" push \
    --path "$ROOT" --tag "$VERSION" --provenance "$PROVENANCE"
python3 "$STANDARDS_ROOT/scripts/formal_release_git.py" verify \
    --path "$ROOT" --tag "$VERSION" --provenance "$PROVENANCE"
python3 scripts/release_tool.py verify-provenance \
    --provenance "$PROVENANCE" --require-remote
bash scripts/publish-update-mirrors.sh "$PROVENANCE"
