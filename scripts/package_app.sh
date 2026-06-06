#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Happy Workdog"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BINARY_NAME="happy-workdog"
ICON_SOURCE="$ROOT_DIR/assets/AppIconSource.png"
ICONSET_DIR="$ROOT_DIR/assets/AppIcon.iconset"
ICNS_PATH="$ROOT_DIR/assets/AppIcon.icns"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
INSTALL_APP=0
RUN_APP=0

usage() {
    cat <<USAGE
Usage: bash scripts/package_app.sh [--install] [--run]

Options:
  --install  Replace "$INSTALL_DIR/$APP_NAME.app" with the freshly built app.
  --run      Launch the freshly built app. Without --install, runs the build app binary directly.
  --help     Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --install)
            INSTALL_APP=1
            ;;
        --run)
            RUN_APP=1
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

stop_running_app() {
    killall "$BINARY_NAME" >/dev/null 2>&1 || true
    sleep 0.4
}

cd "$ROOT_DIR"

# Regenerate the iconset + icns from the source PNG so DPI metadata stays at 72
# and all sizes are in sync. macOS notification center reads from Launch Services'
# icon cache, which only refreshes when the bundle is re-registered (see lsregister
# call near the end of the script).
if [ -f "$ICON_SOURCE" ]; then
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"
    for size in 16 32 128 256 512; do
        sips -s format png -s dpiHeight 72 -s dpiWidth 72 \
            -z "$size" "$size" "$ICON_SOURCE" \
            --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
        retina=$((size * 2))
        sips -s format png -s dpiHeight 72 -s dpiWidth 72 \
            -z "$retina" "$retina" "$ICON_SOURCE" \
            --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns -o "$ICNS_PATH" "$ICONSET_DIR"
else
    echo "Missing $ICON_SOURCE; reusing existing $ICNS_PATH" >&2
fi

find "$ROOT_DIR/.build" -path "*/release/happy-workdog_happy-workdog.bundle" -type d -prune -exec rm -rf {} +
swift build --disable-sandbox -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/$BINARY_NAME" "$MACOS_DIR/$BINARY_NAME"
cp "$ICNS_PATH" "$RESOURCES_DIR/AppIcon.icns"

# Copy SPM resource bundle. SwiftPM includes the architecture in some build paths,
# so discover the bundle instead of hard-coding arm64.
RESOURCE_BUNDLE="$(find "$ROOT_DIR/.build" -path "*/release/happy-workdog_happy-workdog.bundle" -type d | head -n 1)"
if [ -n "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
else
    echo "Missing SPM resource bundle" >&2
    exit 1
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>Happy Workdog</string>
  <key>CFBundleExecutable</key>
  <string>happy-workdog</string>
  <key>CFBundleIdentifier</key>
  <string>com.luobaosong.happy-workdog</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Happy Workdog</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

codesign \
  --force \
  --deep \
  --options runtime \
  --sign "${SIGN_IDENTITY:--}" \
  --identifier "com.luobaosong.happy-workdog" \
  --requirements '=designated => identifier "com.luobaosong.happy-workdog"' \
  "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

# Refresh Launch Services so Notification Center picks up the (possibly new) icon
# the next time the app posts a notification. Without this, macOS keeps serving the
# previously cached icon for this bundle path.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "Built $APP_DIR"

TARGET_APP_DIR="$APP_DIR"
if [ "$INSTALL_APP" -eq 1 ]; then
    INSTALLED_APP_DIR="$INSTALL_DIR/$APP_NAME.app"
    stop_running_app
    rm -rf "$INSTALLED_APP_DIR"
    cp -R "$APP_DIR" "$INSTALLED_APP_DIR"
    TARGET_APP_DIR="$INSTALLED_APP_DIR"
    if [ -x "$LSREGISTER" ]; then
        "$LSREGISTER" -f "$TARGET_APP_DIR" >/dev/null 2>&1 || true
    fi
    echo "Installed $TARGET_APP_DIR"
fi

if [ "$RUN_APP" -eq 1 ]; then
    stop_running_app

    if [ "$INSTALL_APP" -eq 1 ]; then
        open "$TARGET_APP_DIR"
        echo "Launched $TARGET_APP_DIR"
    else
        LOG_PATH="${TMPDIR:-/tmp}/happy-workdog-dev.log"
        "$TARGET_APP_DIR/Contents/MacOS/$BINARY_NAME" >"$LOG_PATH" 2>&1 &
        echo "Launched $TARGET_APP_DIR (pid $!, log: $LOG_PATH)"
    fi
fi
