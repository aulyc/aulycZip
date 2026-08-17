#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-generate}"

if [[ "$MODE" == "--check" ]]; then
    TEMP_ROOT="$(mktemp -d)"
    trap 'rm -rf "$TEMP_ROOT"' EXIT
    /usr/bin/swift "$ROOT/scripts/IconGenerator.swift" "$ROOT" "$TEMP_ROOT"
    for path in \
        design/menuBarIcon.svg \
        design/appIcon.svg \
        design/appIcon-preview.png \
        design/icon-manifest.json \
        Sources/aulycZip/Resources/MenuBarIcon.svg \
        Resources/AppIcon.icns; do
        cmp "$ROOT/$path" "$TEMP_ROOT/$path" >/dev/null || {
            echo "error: generated icon asset is stale: $path" >&2
            exit 1
        }
    done
    echo "Icon assets match design/iconMark.svg"
elif [[ "$MODE" == "generate" ]]; then
    /usr/bin/swift "$ROOT/scripts/IconGenerator.swift" "$ROOT" "$ROOT"
    echo "Generated menu bar and application icons"
else
    echo "usage: scripts/generate-icon.sh [generate|--check]" >&2
    exit 64
fi
