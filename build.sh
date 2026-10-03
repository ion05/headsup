#!/bin/sh
# Builds HeadsUp.app and installs it to ~/Applications.
# SIGN_ID can be overridden; defaults to the first Apple Development identity, else ad-hoc.
# UNIVERSAL=1 builds arm64 + x86_64. INSTALL=0 stops after build/HeadsUp.app (release use).
set -e
cd "$(dirname "$0")"

if [ "${UNIVERSAL:-0}" = 1 ]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN=.build/apple/Products/Release/HeadsUp
else
    swift build -c release
    BIN=.build/release/HeadsUp
fi
APP=build/HeadsUp.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/HeadsUp"
cp Info.plist "$APP/Contents/Info.plist"
cp design/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# ditto keeps the framework's Versions/Current symlinks intact.
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"

SIGN_ID=${SIGN_ID:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')}
SIGN_ID=${SIGN_ID:--}
# Notarization needs a secure timestamp; dev builds skip it so they work offline.
case "$SIGN_ID" in "Developer ID"*) TS=--timestamp ;; *) TS= ;; esac
sign() { codesign --force --options runtime $TS --sign "$SIGN_ID" "$@"; }

# Inside-out, per https://sparkle-project.org/documentation/sandboxing/#code-signing
FW="$APP/Contents/Frameworks/Sparkle.framework"
sign "$FW/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
sign "$FW/Versions/B/Autoupdate"
sign "$FW/Versions/B/Updater.app"
sign "$FW"
sign --entitlements HeadsUp.entitlements "$APP"

[ "${INSTALL:-1}" = 0 ] && { echo "Built $APP (signed: $SIGN_ID)"; exit 0; }

mkdir -p ~/Applications
pkill -x HeadsUp 2>/dev/null || true
rm -rf ~/Applications/HeadsUp.app
cp -R "$APP" ~/Applications/
echo "Installed ~/Applications/HeadsUp.app (signed: $SIGN_ID)"
