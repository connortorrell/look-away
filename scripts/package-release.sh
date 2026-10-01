#!/bin/sh
# Builds a universal Look Away.app and packages it for a GitHub release:
#
#   dist/LookAway.dmg  what people download and drag to Applications
#   dist/LookAway.zip  what the in-app updater downloads (no DMG to mount)
#
# Run through `make dist`. The release workflow sets everything below; locally,
# `make dist VERSION=0.0.0 NOTARIZE=0` does a dry run with an ad hoc signature.
#
#   VERSION         required, e.g. 1.2.0
#   BUILD_NUMBER    optional, CFBundleVersion
#   SIGN_IDENTITY   "-" for ad hoc, or e.g. "Developer ID Application"
#   NOTARIZE        1 to notarize and staple (needs the three NOTARY_ values)
#   NOTARY_KEY      path to the App Store Connect API key (.p8)
#   NOTARY_KEY_ID   that key's ID
#   NOTARY_ISSUER   that key's issuer ID
set -eu
cd "$(dirname "$0")/.."

: "${VERSION:?Set VERSION, e.g. make dist VERSION=1.2.0}"
BUILD_NUMBER=${BUILD_NUMBER:-}
SIGN_IDENTITY=${SIGN_IDENTITY:--}
NOTARIZE=${NOTARIZE:-1}

APP="build/Look Away.app"
DIST=dist

notarize() {
    xcrun notarytool submit "$1" \
        --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" \
        --wait
}

# Where a universal build lands differs between toolchains; ask SwiftPM.
ARCH_FLAGS="--arch arm64 --arch x86_64"
BIN_PATH=$(swift build -c release $ARCH_FLAGS --show-bin-path)

make bundle \
    ARCH_FLAGS="$ARCH_FLAGS" \
    BINARY="$BIN_PATH/LookAway" \
    VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" SIGN_IDENTITY="$SIGN_IDENTITY"

rm -rf "$DIST"
mkdir -p "$DIST"

# The app is notarized and stapled on its own first, so the copy people drag
# out of the DMG opens without Gatekeeper having to reach Apple.
if [ "$NOTARIZE" = 1 ]; then
    ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"
    notarize "$DIST/notarize.zip"
    rm "$DIST/notarize.zip"
    xcrun stapler staple "$APP"
fi

ditto -c -k --keepParent "$APP" "$DIST/LookAway.zip"

STAGING="$DIST/dmg"
mkdir "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Look Away" -srcfolder "$STAGING" -format UDZO -ov "$DIST/LookAway.dmg"
rm -rf "$STAGING"

if [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DIST/LookAway.dmg"
fi
if [ "$NOTARIZE" = 1 ]; then
    notarize "$DIST/LookAway.dmg"
    xcrun stapler staple "$DIST/LookAway.dmg"
fi

echo "Packaged Look Away $VERSION:"
ls -l "$DIST"
