#!/bin/sh
# Runs the app's tests on a throwaway simulator of its own, then deletes it.
#
# Why: XCTest kills any running copy of DLChat on a simulator when a UI test starts there
# ("Terminating for automation testing"). Two test runs on the same named simulator, e.g. from two
# worktrees at once, kill each other's test app with no crash log. A simulator per run avoids that.
#
# Usage: sh scripts/test-app.sh [extra xcodebuild arguments, e.g. -only-testing:DLChatTests]
set -eu
cd "$(dirname "$0")/.."

DEVICE_TYPE="${DLCHAT_SIM_DEVICE:-iPhone 18 Pro}"
NAME="dlchat-test-$$-$(date +%s)"
UDID=$(xcrun simctl create "$NAME" "$DEVICE_TYPE")
cleanup() { xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true; xcrun simctl delete "$UDID" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM

echo "Testing on throwaway simulator $NAME ($UDID)"
xcodebuild test -project DLChat.xcodeproj -scheme DLChat \
  -destination "platform=iOS Simulator,id=$UDID" \
  -skip-testing:DLChatTests/RealRelaySmokeTests -skip-testing:DLChatUITests/ScreenshotTour \
  "$@"
