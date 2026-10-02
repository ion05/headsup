#!/bin/sh
# Builds HeadsUp.app and installs it to ~/Applications.
# SIGN_ID can be overridden; defaults to the first Apple Development identity, else ad-hoc.
set -e
cd "$(dirname "$0")"

swift build -c release
APP=build/HeadsUp.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/HeadsUp "$APP/Contents/MacOS/HeadsUp"
cp Info.plist "$APP/Contents/Info.plist"

SIGN_ID=${SIGN_ID:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')}
codesign --force --options runtime --entitlements HeadsUp.entitlements --sign "${SIGN_ID:--}" "$APP"

mkdir -p ~/Applications
pkill -x HeadsUp 2>/dev/null || true
rm -rf ~/Applications/HeadsUp.app
cp -R "$APP" ~/Applications/
echo "Installed ~/Applications/HeadsUp.app (signed: ${SIGN_ID:-ad-hoc})"
