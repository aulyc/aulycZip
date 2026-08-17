#!/bin/bash
set -euo pipefail

STANDARDS_ROOT="${STANDARDS_ROOT:-/Users/crp/Projects/Codex 开发规范}"
TOOL="$STANDARDS_ROOT/scripts/dual_mirror_release.py"
[[ -f "$TOOL" ]] || { echo "error: central dual-mirror tool is unavailable" >&2; exit 1; }

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
