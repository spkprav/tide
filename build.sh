#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Usage:
#   ./build.sh                       # debug build → Tide-dev.app
#   CONFIG=release ./build.sh        # release build → Tide.app
#   ./build.sh install               # release build + copy to /Applications
#
# Debug and release use distinct bundle ids, app names, and data directories so
# you can iterate on Tide-dev.app while the installed Tide.app keeps its state.

CONFIG="${CONFIG:-debug}"
SUBCMD="${1:-build}"
if [ "$SUBCMD" = "install" ]; then
    CONFIG="release"
fi

if [ "$CONFIG" = "release" ]; then
    APP_NAME="Tide"
    BUNDLE_ID="local.pk.Tide"
    DISPLAY_NAME="Tide"
else
    APP_NAME="Tide-dev"
    BUNDLE_ID="local.pk.Tide.dev"
    DISPLAY_NAME="Tide (dev)"
fi
APP="$APP_NAME.app"

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
BIN_PATH=".build/$CONFIG/Tide"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$APP_NAME"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
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

# 4. Bundle tmux (optional — silent skip if no system tmux available)
bundle_tmux() {
    local sys_tmux
    sys_tmux=$(command -v tmux || true)
    if [ -z "$sys_tmux" ]; then
        echo "==> tmux not found on PATH — skipping bundle (persistent panes will require system tmux)"
        return 0
    fi
    echo "==> Bundling $sys_tmux into $APP/Contents/Resources"

    local bin_dir="$APP/Contents/Resources/bin"
    local lib_dir="$APP/Contents/Resources/lib"
    mkdir -p "$bin_dir" "$lib_dir"
    cp "$sys_tmux" "$bin_dir/tmux"
    chmod +x "$bin_dir/tmux"

    # Walk dependencies and copy any non-system dylibs Tide doesn't already have.
    # System dylibs live under /usr/lib or /System/Library — skip those.
    local queue=("$bin_dir/tmux")
    local seen=""
    while [ ${#queue[@]} -gt 0 ]; do
        local target="${queue[0]}"
        queue=("${queue[@]:1}")
        case " $seen " in *" $target "*) continue ;; esac
        seen="$seen $target"

        # Each dep line: "\tpath (compatibility version ...)"
        while IFS= read -r line; do
            local dep
            dep=$(echo "$line" | awk '{print $1}')
            [ -z "$dep" ] && continue
            case "$dep" in
                /usr/lib/*|/System/*|/usr/bin/*) continue ;;
                @rpath/*|@loader_path/*|@executable_path/*) continue ;;
            esac
            local name
            name=$(basename "$dep")
            local local_path="$lib_dir/$name"
            if [ ! -f "$local_path" ]; then
                if [ -f "$dep" ]; then
                    cp "$dep" "$local_path"
                    chmod u+w "$local_path"
                    install_name_tool -id "@executable_path/../Resources/lib/$name" "$local_path" 2>/dev/null || true
                    queue+=("$local_path")
                fi
            fi
            install_name_tool -change "$dep" "@executable_path/../Resources/lib/$name" "$target" 2>/dev/null || true
        done < <(otool -L "$target" | tail -n +2)
    done

    # Sanity: confirm bundled tmux runs.
    if ! "$bin_dir/tmux" -V > /dev/null 2>&1; then
        echo "==> WARN: bundled tmux failed self-test. Removing — fall back to system tmux."
        rm -rf "$bin_dir" "$lib_dir"
    fi
}
bundle_tmux

# Refresh icon cache so Dock picks up new icon
touch "$APP"

codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "==> Built $(pwd)/$APP"

# 5. Install target — copy release build into /Applications
if [ "$SUBCMD" = "install" ]; then
    DEST="/Applications/$APP"
    echo "==> Installing to $DEST"
    if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
        echo "    Quitting running $APP_NAME first…"
        osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || killall "$APP_NAME" 2>/dev/null || true
        sleep 1
    fi
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    # Re-sign in destination so Gatekeeper doesn't complain about modified paths.
    codesign --force --deep --sign - "$DEST" 2>/dev/null || true
    echo "==> Installed. Launch with: open \"$DEST\""
fi
