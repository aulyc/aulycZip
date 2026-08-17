#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROVENANCE="$(cd "$(dirname "${1:?usage: install-release.sh <provenance>}")" && pwd)/$(basename "$1")"
DMG="$(python3 -c 'import json,os,sys; p=json.load(open(sys.argv[1], encoding="utf-8")); print(os.path.join(os.path.dirname(sys.argv[1]), p["artifacts"][0]["file"]))' "$PROVENANCE")"
TARGET="/Applications/aulycZip.app"
STAGED="/Applications/.aulycZip-install-$$.app"
BACKUP="/Applications/.aulycZip-backup-$$.app"

cd "$ROOT"
python3 scripts/release_tool.py verify-provenance \
    --provenance "$PROVENANCE" --require-remote
pgrep -x aulycZip >/dev/null 2>&1 && {
    echo "error: quit aulycZip before installation" >&2
    exit 1
}
[[ ! -e "$STAGED" && ! -e "$BACKUP" ]] || {
    echo "error: temporary installation path is occupied" >&2
    exit 1
}

TEMP_ROOT="$(mktemp -d)"
MOUNT="$TEMP_ROOT/mount"
mkdir -p "$MOUNT"
MOUNTED=false
cleanup() {
    [[ "$MOUNTED" == false ]] || hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
    [[ ! -e "$STAGED" ]] || rm -rf "$STAGED"
    rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT"
MOUNTED=true
/usr/bin/ditto "$MOUNT/aulycZip.app" "$STAGED"
python3 scripts/release_tool.py verify-app \
    --app "$STAGED" --provenance "$PROVENANCE" --require-remote
hdiutil detach "$MOUNT"
MOUNTED=false

HAD_EXISTING=false
if [[ -e "$TARGET" ]]; then
    mv "$TARGET" "$BACKUP"
    HAD_EXISTING=true
fi
if mv "$STAGED" "$TARGET" && python3 scripts/release_tool.py verify-app \
    --app "$TARGET" --provenance "$PROVENANCE" --require-remote; then
    [[ "$HAD_EXISTING" == false ]] || rm -rf "$BACKUP"
    echo "Installed verified formal release: $TARGET"
else
    [[ ! -e "$TARGET" ]] || rm -rf "$TARGET"
    [[ "$HAD_EXISTING" == false ]] || mv "$BACKUP" "$TARGET"
    echo "error: installation failed; previous app restored" >&2
    exit 1
fi
