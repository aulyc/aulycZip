#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:?DEVELOPER_ID_APPLICATION is required}"
NOTARY_PROFILE="${NOTARY_PROFILE:?NOTARY_PROFILE is required}"
cd "$ROOT"

[[ -z "$(git status --porcelain --untracked-files=all)" ]] || {
    echo "error: formal release requires a clean worktree" >&2
    exit 1
}
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Config/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Config/Info.plist)"
git rev-parse --verify "refs/tags/$VERSION^{tag}" >/dev/null
[[ "$(git rev-list -n 1 "$VERSION")" == "$(git rev-parse HEAD)" ]] || {
    echo "error: formal tag does not point to HEAD" >&2
    exit 1
}

DIST="$ROOT/dist"
mkdir -p "$DIST"
STEM="aulycZip-$VERSION-build.$BUILD-formal-macos-arm64"
DMG="$DIST/$STEM.dmg"
PROVENANCE="$DIST/$STEM.release-provenance.json"
NOTARY_RESULT="$DIST/$STEM.notarytool.json"
for output in "$DMG" "$PROVENANCE" "$NOTARY_RESULT"; do
    [[ ! -e "$output" ]] || { echo "error: refusing to overwrite $output" >&2; exit 1; }
done

TEMP_ROOT="$(mktemp -d)"
SOURCE="$TEMP_ROOT/source"
cleanup() {
    git -C "$ROOT" worktree remove --force "$SOURCE" >/dev/null 2>&1 || true
    rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

git worktree add --detach "$SOURCE" "$VERSION"
[[ -z "$(git -C "$SOURCE" status --porcelain --untracked-files=all)" ]] || {
    echo "error: exact-tag source is dirty before build" >&2
    exit 1
}

APP_OUTPUT="$TEMP_ROOT/app"
AULYCZIP_APP_OUTPUT_DIR="$APP_OUTPUT" \
AULYCZIP_RELEASE_CHANNEL=formal \
AULYCZIP_RELEASE_TAG="$VERSION" \
SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
    bash "$SOURCE/scripts/bundle.sh" --release
APP="$APP_OUTPUT/aulycZip.app"

DMG_STAGE="$TEMP_ROOT/dmg-stage"
mkdir -p "$DMG_STAGE"
/usr/bin/ditto "$APP" "$DMG_STAGE/aulycZip.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "aulycZip $VERSION" -srcfolder "$DMG_STAGE" \
    -format UDZO -ov "$DMG"
codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DMG"
codesign --verify --verbose=2 "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" \
    --wait --output-format json > "$NOTARY_RESULT"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -vvv -t open --context context:primary-signature "$DMG"

python3 "$SOURCE/scripts/release_tool.py" write-provenance \
    --source-root "$SOURCE" \
    --app "$APP" \
    --dmg "$DMG" \
    --output "$PROVENANCE" \
    --tag "$VERSION" \
    --notary-result "$NOTARY_RESULT"
(
    cd "$DIST"
    shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256"
    shasum -a 256 "$(basename "$PROVENANCE")" > "$(basename "$PROVENANCE").sha256"
)
python3 "$SOURCE/scripts/release_tool.py" verify-provenance --provenance "$PROVENANCE"

[[ -z "$(git -C "$SOURCE" status --porcelain --untracked-files=all)" ]] || {
    echo "error: exact-tag source is dirty after build" >&2
    exit 1
}
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || {
    echo "error: calling worktree changed during formal build" >&2
    exit 1
}
echo "Formal artifact: $DMG"
echo "Release provenance: $PROVENANCE"
