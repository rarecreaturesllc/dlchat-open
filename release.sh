#!/bin/bash
# One command to put DLChat on TestFlight. Dry run (archive only) unless --live.
# Usage: ./release.sh [ios] [--live] [--track internal|production]
#   internal (default) = TestFlight. production refuses: the App Store is blocked by the open
#   legal and crypto reviews in docs/launch-blockers.md (FCC attorney review, cryptographer review).
# Build number: one above CURRENT_PROJECT_VERSION in the project; --live writes it back (commit it as "Build N").
# Needs a Mac with Xcode, scripts/fetch-tor.sh run once, and ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH.
set -euo pipefail
cd "$(dirname "$0")"
usage="usage: ./release.sh [ios] [--live] [--track internal|production]"
live=false track=internal
while [ $# -gt 0 ]; do
  case "$1" in
    ios) ;;
    mac|android|chrome|firefox|all) echo "$1: not shipped from this repo (DLChat is iPhone only)." >&2; exit 2 ;;
    --live) live=true ;;
    --track) track=${2:-}; shift ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
  shift
done
case "$track" in
  internal) ;;
  production)
    echo "The App Store is blocked until these reviews clear (docs/launch-blockers.md):" >&2
    grep -E '^\| 6 \|.*\| OPEN|^\| [0-9]+ \|.*App Store (submission|release).*\| OPEN' docs/launch-blockers.md | cut -c1-200 >&2 || true
    echo "Only TestFlight ships from here: ./release.sh --live" >&2
    exit 1 ;;
  *) echo "$usage" >&2; exit 2 ;;
esac
[ "$(uname)" = Darwin ] || { echo "needs a Mac with Xcode" >&2; exit 1; }
for v in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH; do
  [ -n "${!v:-}" ] || { echo "missing env var $v (App Store Connect API key, in ~/.zshrc)" >&2; exit 1; }
done
[ -d Packages/TorKit/tor.xcframework ] || sh scripts/fetch-tor.sh
pbx=DLChat.xcodeproj/project.pbxproj
n=$(( $(grep -oE 'CURRENT_PROJECT_VERSION = [0-9]+' "$pbx" | grep -oE '[0-9]+' | sort -n | tail -1) + 1 ))
version=$(grep -oE 'MARKETING_VERSION = [0-9.]+' "$pbx" | head -1 | grep -oE '[0-9.]+$')
auth=(-allowProvisioningUpdates -authenticationKeyPath "${ASC_KEY_PATH/#\~/$HOME}"
      -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
archive="build/DLChat-$version-$n.xcarchive"
echo "archiving DLChat $version ($n)"
xcodebuild -project DLChat.xcodeproj -scheme DLChat -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$archive" "${auth[@]}" CURRENT_PROJECT_VERSION="$n" archive -quiet
echo "archived: $archive"
if [ "$live" != true ]; then echo "Dry run: not uploaded. Add --live to upload build $n to TestFlight."; exit 0; fi
xcodebuild -exportArchive -archivePath "$archive" -exportPath "build/export-$n" \
  -exportOptionsPlist Config/ExportOptions-TestFlight.plist "${auth[@]}"
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $n;/" "$pbx"
echo "Uploaded DLChat $version ($n). The project now says build $n: commit it as \"Build $n\"."
echo "TestFlight: https://appstoreconnect.apple.com/apps/6831788539/testflight (after Apple's processing, 5-30 min)."
