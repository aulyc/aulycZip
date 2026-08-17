#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-debug}"
for argument in "$@"; do
    case "$argument" in
        --debug) CONFIG="debug" ;;
        --release) CONFIG="release" ;;
        *) echo "error: unsupported bundle argument: $argument" >&2; exit 64 ;;
    esac
done

[[ "$CONFIG" == "debug" || "$CONFIG" == "release" ]] || {
    echo "error: CONFIG must be debug or release" >&2
    exit 64
}

scripts/generate-icon.sh --check
swift build -c "$CONFIG" --arch arm64
BIN_DIR="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"
BINARY="$BIN_DIR/aulycZip"
[[ -f "$BINARY" ]] || { echo "error: app binary not found" >&2; exit 1; }

APP_ROOT="${AULYCZIP_APP_OUTPUT_DIR:-$ROOT/.cache/build}"
APP="$APP_ROOT/aulycZip.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BINARY" "$MACOS/aulycZip"
cp Config/Info.plist "$CONTENTS/Info.plist"
cp Resources/AppIcon.icns "$RESOURCES/AppIcon.icns"
cp design/menuBarIcon.svg "$RESOURCES/MenuBarIcon.svg"

codesign --force --options runtime --timestamp=none --sign - "$APP"
codesign --verify --strict --verbose=2 "$APP"

ARCHITECTURES="$(lipo -archs "$MACOS/aulycZip")"
[[ "$ARCHITECTURES" == "arm64" ]] || {
    echo "error: expected arm64 app binary, found: $ARCHITECTURES" >&2
    exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$CONTENTS/Info.plist")" == "true" ]] || {
    echo "error: LSUIElement must be true" >&2
    exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSServices:0:NSMessage' "$CONTENTS/Info.plist")" == "createEncryptedZip" ]] || {
    echo "error: Finder encrypted ZIP service message is missing" >&2
    exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSServices:0:NSSendFileTypes:0' "$CONTENTS/Info.plist")" == "public.item" ]] || {
    echo "error: Finder service must receive public.item file URLs" >&2
    exit 1
}

echo "Built local app: $APP"
echo "Architecture: $ARCHITECTURES"
