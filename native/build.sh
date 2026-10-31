#!/bin/bash
#
# Builds a native Apple silicon .app bundle.
#
#   ./build.sh            # arm64 (default)
#   ARCHS="arm64 x86_64"  ./build.sh   # universal
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="TascamUSControl"
BUNDLE_NAME="TASCAM US Control"
BUILD_DIR="build"
APP="$BUILD_DIR/$BUNDLE_NAME.app"
CONTENTS="$APP/Contents"
ARCHS="${ARCHS:-arm64}"
MIN_MACOS="${MIN_MACOS:-13.0}"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

echo "==> Compiling app ($ARCHS)"
SWIFT_FLAGS=(-O -whole-module-optimization -swift-version 5)
LINK_FLAGS=(-framework SwiftUI -framework AppKit -framework IOKit -framework IOUSBHost)

BINARIES=()
for ARCH in $ARCHS; do
    OUT="$BUILD_DIR/$APP_NAME-$ARCH"
    echo "    - $ARCH"
    swiftc "${SWIFT_FLAGS[@]}" \
        -target "${ARCH}-apple-macos${MIN_MACOS}" \
        Sources/*.swift \
        "${LINK_FLAGS[@]}" \
        -o "$OUT"
    BINARIES+=("$OUT")
done

if [ "${#BINARIES[@]}" -eq 1 ]; then
    cp "${BINARIES[0]}" "$CONTENTS/MacOS/$APP_NAME"
else
    echo "==> Creating universal binary"
    lipo -create "${BINARIES[@]}" -output "$CONTENTS/MacOS/$APP_NAME"
fi

chmod +x "$CONTENTS/MacOS/$APP_NAME"
cp Sources/Info.plist "$CONTENTS/Info.plist"
cp Resources/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"

# Ad-hoc signature. Enough for local use; replace with a Developer ID
# identity for distribution.
echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" >/dev/null

echo "==> Done: $APP"
file "$CONTENTS/MacOS/$APP_NAME"
