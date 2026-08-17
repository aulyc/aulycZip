#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-debug}"
RELEASE_CHANNEL="${AULYCZIP_RELEASE_CHANNEL:-local}"
RELEASE_TAG="${AULYCZIP_RELEASE_TAG:-local}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
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
[[ "$RELEASE_CHANNEL" == "local" || "$RELEASE_CHANNEL" == "candidate" || "$RELEASE_CHANNEL" == "formal" ]] || {
    echo "error: AULYCZIP_RELEASE_CHANNEL must be local, candidate, or formal" >&2
    exit 64
}

GIT_COMMIT="$(git rev-parse HEAD 2>/dev/null || true)"
[[ "$GIT_COMMIT" =~ ^[0-9a-f]{40}$ ]] || GIT_COMMIT="local"
GIT_DIRTY=false
[[ -z "$(git status --porcelain --untracked-files=normal 2>/dev/null)" ]] || GIT_DIRTY=true
if [[ "$RELEASE_CHANNEL" == "formal" ]]; then
    [[ "$CONFIG" == "release" ]] || { echo "error: formal bundle requires release configuration" >&2; exit 1; }
    [[ "$RELEASE_TAG" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
        echo "error: formal bundle requires a stable AULYCZIP_RELEASE_TAG" >&2
        exit 1
    }
    [[ "$GIT_DIRTY" == false && "$GIT_COMMIT" != "local" ]] || {
        echo "error: formal bundle requires clean Git source" >&2
        exit 1
    }
fi

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

/usr/libexec/PlistBuddy -c "Add :AulycZipGitCommit string $GIT_COMMIT" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :AulycZipReleaseChannel string $RELEASE_CHANNEL" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :AulycZipReleaseTag string $RELEASE_TAG" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :AulycZipBuildDirty bool $GIT_DIRTY" "$CONTENTS/Info.plist"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --options runtime --timestamp=none --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
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
