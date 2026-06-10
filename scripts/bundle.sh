#!/bin/bash
# Builds Portain in release mode and packages it into a double-clickable .app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Portain"
BUNDLE="$ROOT/$APP_NAME.app"
CONTENTS="$BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

echo "▸ Building release binary…"
swift build -c release

echo "▸ Assembling $APP_NAME.app…"
rm -rf "$BUNDLE"
mkdir -p "$MACOS" "$RES"
cp "$ROOT/.build/release/$APP_NAME" "$MACOS/$APP_NAME"

cp "$ROOT/scripts/Info.plist" "$CONTENTS/Info.plist"

# Generate an app icon from SF Symbol-style vector if iconutil + a source exist.
if [ -f "$ROOT/scripts/AppIcon.icns" ]; then
    cp "$ROOT/scripts/AppIcon.icns" "$RES/AppIcon.icns"
fi

# Ad-hoc codesign so Gatekeeper lets it launch locally.
codesign --force --deep --sign - "$BUNDLE" >/dev/null 2>&1 || true

echo "✓ Built $BUNDLE"
echo "  Launch with:  open \"$BUNDLE\""
