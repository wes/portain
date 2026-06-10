#!/bin/bash
# Builds a universal (Apple Silicon + Intel) Portain.app and packages a
# .dmg and .zip ready to attach to a GitHub Release.
#
# Usage: scripts/release.sh [version]
#   version  defaults to the latest git tag (without a leading "v"),
#            then to the value in scripts/Info.plist.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Portain"
DIST="$ROOT/dist"

# --- Resolve version -------------------------------------------------------
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
fi
if [ -z "$VERSION" ]; then
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' scripts/Info.plist 2>/dev/null || echo 0.0.0)"
fi
echo "▸ Releasing $APP_NAME $VERSION"

# --- Build a universal release binary --------------------------------------
echo "▸ Building universal release binary (arm64 + x86_64)…"
swift build -c release --arch arm64 --arch x86_64

BIN=""
for candidate in \
    "$ROOT/.build/apple/Products/Release/$APP_NAME" \
    "$ROOT/.build/release/$APP_NAME"; do
    if [ -f "$candidate" ]; then BIN="$candidate"; break; fi
done
[ -n "$BIN" ] || { echo "✗ Could not locate built binary"; exit 1; }
echo "  $(file "$BIN" | cut -d: -f2-)"

# --- Assemble the .app bundle ----------------------------------------------
echo "▸ Assembling $APP_NAME.app…"
BUNDLE="$ROOT/$APP_NAME.app"
CONTENTS="$BUNDLE/Contents"
rm -rf "$BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT/scripts/Info.plist" "$CONTENTS/Info.plist"
[ -f "$ROOT/scripts/AppIcon.icns" ] && cp "$ROOT/scripts/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$CONTENTS/Info.plist"

# Ad-hoc signature so Gatekeeper allows a local launch.
codesign --force --deep --sign - "$BUNDLE" >/dev/null 2>&1 || true

# --- Package ---------------------------------------------------------------
rm -rf "$DIST"
mkdir -p "$DIST"

ZIP="$DIST/$APP_NAME-$VERSION.zip"
echo "▸ Zipping → $(basename "$ZIP")"
ditto -c -k --keepParent "$BUNDLE" "$ZIP"

DMG="$DIST/$APP_NAME-$VERSION.dmg"
echo "▸ Building disk image → $(basename "$DMG")"
STAGE="$(mktemp -d)"
cp -R "$BUNDLE" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "▸ Writing checksums → SHA256SUMS.txt"
( cd "$DIST" && shasum -a 256 *.dmg *.zip > SHA256SUMS.txt )

echo
echo "✓ Done. Artifacts in dist/:"
ls -lh "$DIST" | tail -n +2 | sed 's/^/  /'
echo
echo "Publish with:"
echo "  gh release create v$VERSION \\"
echo "    dist/$APP_NAME-$VERSION.dmg dist/$APP_NAME-$VERSION.zip dist/SHA256SUMS.txt \\"
echo "    --title \"$APP_NAME $VERSION\" --generate-notes"
