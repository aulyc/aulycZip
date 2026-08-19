#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/standards-dependency.sh"
require_standards_root \
    standards/version.json \
    scripts/standards_check.py

python3 "$STANDARDS_ROOT/scripts/standards_check.py" project --path "$ROOT" "$@"
