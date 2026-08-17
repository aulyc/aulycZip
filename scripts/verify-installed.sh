#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROVENANCE="$(cd "$(dirname "${1:?usage: verify-installed.sh <provenance>}")" && pwd)/$(basename "$1")"
cd "$ROOT"
python3 scripts/release_tool.py verify-app \
    --app /Applications/aulycZip.app \
    --provenance "$PROVENANCE" \
    --require-remote
