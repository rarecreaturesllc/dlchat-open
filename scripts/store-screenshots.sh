#!/bin/sh
# Makes the App Store screenshots: store/ios/screenshots/en-US/*.png, 1320x2868 (iPhone 6.9"), no alpha.
# DLChat is iPhone only, so there is no iPad set.
#
# Builds the Debug app, opens each screen with the `-store-shots` demo content (group, draft and
# conversation, seeded in GroupModel and GroupBook) on a throwaway simulator of its own, then
# scripts/store-frame.py puts each caption above its screen. Captions live in store-frame.py.
# Online chat points at a dead local relay with Tor off, so nothing leaves the Mac.
#
# Needs: Xcode, scripts/fetch-tor.sh run once, python3 with Pillow (pip3 install pillow).
# Usage: sh scripts/store-screenshots.sh
set -eu
cd "$(dirname "$0")/.."

BUNDLE=com.harrisonfischberg.dlchat
OUT=store/ios/screenshots/en-US
WORK=$(mktemp -d)
UDID=$(xcrun simctl create "dlchat-store-$$" "iPhone 17 Pro Max")
cleanup() { xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true; xcrun simctl delete "$UDID" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

xcodebuild -project DLChat.xcodeproj -scheme DLChat -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$WORK/dd" build -quiet
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" >/dev/null
xcrun simctl install "$UDID" "$WORK/dd/Build/Products/Debug-iphonesimulator/DLChat.app"
# The status bar clock matches the times on the seeded chat messages, which end just before now.
xcrun simctl status_bar "$UDID" override --time "$(date +%H:%M)" --batteryState charged --batteryLevel 100

n=0
for screen in compose readout tones qr chat safety; do
  n=$((n + 1))
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" -seed-demo -reset-demo -store-shots -no-tor \
    -online-relays ws://127.0.0.1:1 -screen "$screen" >/dev/null
  sleep 6
  xcrun simctl io "$UDID" screenshot "$WORK/0$n-$screen.png" >/dev/null 2>&1
done

mkdir -p "$OUT"
python3 scripts/store-frame.py "$WORK" "$OUT"
