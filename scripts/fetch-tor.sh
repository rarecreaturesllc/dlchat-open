#!/bin/sh
# Fetches iCepa's prebuilt tor.xcframework (tor, OpenSSL, libevent, liblzma) and checks it
# against the SHA-256 published in their Tor.podspec for this version. Run once after cloning.
set -eu
VERSION=v409.14.1
SHA256=823d98fcafd8eba089f31b32989ad70e15a0e8a1b5709bc0d5941fb09ef1b625
DEST="$(cd "$(dirname "$0")/.." && pwd)/Packages/TorKit"
[ -d "$DEST/tor.xcframework" ] && { echo "tor.xcframework already present"; exit 0; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl --fail --location --progress-bar -o "$TMP/tor.zip" \
  "https://github.com/iCepa/Tor.framework/releases/download/$VERSION/tor.xcframework.zip"
ACTUAL="$(shasum -a 256 "$TMP/tor.zip" | awk '{print $1}')"
[ "$ACTUAL" = "$SHA256" ] || { echo "Checksum mismatch: $ACTUAL"; exit 1; }
unzip -q "$TMP/tor.zip" -d "$TMP/out"
# Repackage the iOS slices as a static-library xcframework: iCepa ships macOS-style deep
# frameworks, which Xcode would copy into the app bundle and iOS then rejects. A static
# library is linked in and never copied.
ARGS=""
for SLICE in ios-arm64 ios-arm64_x86_64-simulator macos-arm64_x86_64; do
  FW="$TMP/out/tor.xcframework/$SLICE/tor.framework/Versions/A"
  OUT="$TMP/lib/$SLICE"
  mkdir -p "$OUT"
  cp "$FW/tor" "$OUT/libtor.a"
  cp -R "$FW/Headers" "$OUT/Headers"
  printf 'module tor {\n    umbrella header "tor_umbrella.h"\n    export *\n}\n' > "$OUT/Headers/module.modulemap"
  ARGS="$ARGS -library $OUT/libtor.a -headers $OUT/Headers"
done
xcodebuild -create-xcframework $ARGS -output "$DEST/tor.xcframework" >/dev/null
echo "tor.xcframework $VERSION verified and installed"
