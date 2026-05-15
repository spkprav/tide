#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-debug}"

# 1. Build binary
echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

# 2. Generate icon if missing or stale
ICONSET="Tide.iconset"
ICNS="Tide.icns"
SVG="assets/icon.svg"

if [ ! -f "$ICNS" ] || [ "$SVG" -nt "$ICNS" ]; then
    echo "==> Generating $ICNS from $SVG"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    swift scripts/generate_icon.swift "$SVG" "$ICONSET" > /dev/null
    iconutil -c icns "$ICONSET" -o "$ICNS"
fi

# 3. Assemble .app bundle
APP="Tide.app"
BIN_PATH=".build/$CONFIG/Tide"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/Tide"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Tide</string>
  <key>CFBundleIdentifier</key><string>local.pk.Tide</string>
  <key>CFBundleName</key><string>Tide</string>
  <key>CFBundleDisplayName</key><string>Tide</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

# Refresh icon cache so Dock picks up new icon
touch "$APP"

codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "==> Built $(pwd)/$APP"
