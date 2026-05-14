#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexSessionCleaner"
VOLUME_NAME="Codex Session Cleaner"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
STAGING_DIR="$DIST_DIR/dmg-staging"

"$ROOT_DIR/script/build_and_run.sh" --build

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

/usr/bin/codesign --verify --deep --strict "$STAGING_DIR/$APP_NAME.app"
/usr/bin/hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null
/usr/bin/hdiutil verify "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"
echo "$DMG_PATH"
