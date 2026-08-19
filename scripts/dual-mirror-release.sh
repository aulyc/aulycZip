#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/standards-dependency.sh"
require_standards_root \
    standards/version.json \
    scripts/dual_mirror_release.py
TOOL="$STANDARDS_ROOT/scripts/dual_mirror_release.py"

PHASE="${1:?usage: dual-mirror-release.sh <phase> [arguments...]}"
shift

case "$PHASE" in
    prepare|gitee-auth-check)
        python3 "$TOOL" "$PHASE" --project aulyczip "$@"
        ;;
    preflight|publish|verify)
        python3 "$TOOL" "$PHASE" "$@"
        ;;
    *)
        echo "error: unsupported dual-mirror phase: $PHASE" >&2
        exit 64
        ;;
esac
