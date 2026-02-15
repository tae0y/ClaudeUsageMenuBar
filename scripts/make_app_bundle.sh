#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ClaudeUsageMenuBar"
BUNDLE_ID="com.local.claudeusagemenubar"

cd "$ROOT_DIR"

swift build -c release

# SwiftPM puts the product binary under .build/<triple>/release/<name>
BIN_PATH=""
for p in \
  ".build/arm64-apple-macosx/release/${APP_NAME}" \
  ".build/x86_64-apple-macosx/release/${APP_NAME}" \
  ".build/release/${APP_NAME}"; do
  if [[ -f "$p" ]]; then
    BIN_PATH="$p"
    break
  fi
done

if [[ -z "$BIN_PATH" ]]; then
  echo "Could not locate release binary for ${APP_NAME}." >&2
  exit 1
fi

OUT_DIR="$ROOT_DIR/dist"
APP_DIR="$OUT_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$BIN_PATH" "$MACOS_DIR/${APP_NAME}"
chmod +x "$MACOS_DIR/${APP_NAME}"

# Minimal Info.plist for a menu bar app.
cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign to reduce gatekeeper issues for local use.
if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - --timestamp=none "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "Built: $APP_DIR"
