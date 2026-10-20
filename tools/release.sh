#!/bin/zsh
# Builds the public 1Cleaner DMG: universal Release signed with Developer ID, notarized by Apple and stapled, so it
# opens on any Mac without Gatekeeper warnings. Output: build/dist/1Cleaner-<version>-<build>.dmg.
#
#   SIGNING_IDENTITY="Developer ID Application: Name (TEAMID)" TEAM_ID=TEAMID tools/release.sh
#   ... tools/release.sh --no-notarize   build and sign only (nothing is sent to Apple)
#
# Needs: a "Developer ID Application" certificate with its private key in the login keychain (codesign may ask
# once to use the key: Always Allow), and an App Store Connect API key in ~/.appstoreconnect/config.json for
# notarization. The signing identity and team come only from SIGNING_IDENTITY and TEAM_ID; nothing of the
# maintainer's is kept here. To build without any Apple account, see "Build from source" in README.md.
set -euo pipefail

IDENTITY="${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application identity}"
TEAM="${TEAM_ID:?Set TEAM_ID to your Apple Developer team ID}"
NOTARIZE=1
[[ "${1:-}" == "--no-notarize" ]] && NOTARIZE=0

APP_DIR="${0:A:h:h}"
BUILD="$APP_DIR/build"
DERIVED="$BUILD/ReleaseDerivedData"
PRODUCT="$DERIVED/Build/Products/Release/1Cleaner.app"
STAGING="$BUILD/dmg-staging"
DIST="$BUILD/dist"

security find-identity -v -p codesigning | grep -q "$IDENTITY" \
    || { echo "Missing signing identity: $IDENTITY" >&2; exit 1; }

echo "Building and signing…"
rm -rf "$DERIVED"
xcodebuild -project "$APP_DIR/OneCleanerMac.xcodeproj" -scheme OneCleanerMac -configuration Release \
    -derivedDataPath "$DERIVED" -destination "generic/platform=macOS" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" PROVISIONING_PROFILE_SPECIFIER="" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build \
    | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

# Hardened runtime, secure timestamp, the Developer ID chain and no debugging entitlement (get-task-allow, which a
# plain build injects unless CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO) are what notarization checks.
codesign --verify --deep --strict --verbose=2 "$PRODUCT"
codesign -dvv "$PRODUCT" 2>&1 | grep -E "^Authority=Developer ID Application|^Timestamp=|flags=.*runtime" | sed 's/^/  /'
if codesign -d --entitlements - "$PRODUCT" 2>/dev/null | grep -q get-task-allow; then
    echo "The app still has the get-task-allow entitlement; Apple rejects it." >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PRODUCT/Contents/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PRODUCT/Contents/Info.plist")
DMG="$DIST/1Cleaner-$VERSION-$BUILD_NUMBER.dmg"

echo "Packing $DMG…"
rm -rf "$STAGING"
mkdir -p "$STAGING" "$DIST"
ditto "$PRODUCT" "$STAGING/1Cleaner.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "1Cleaner $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
codesign --sign "$IDENTITY" --timestamp "$DMG"

if (( NOTARIZE )); then
    CONFIG="$HOME/.appstoreconnect/config.json"
    KEY_ID=$(/usr/bin/python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['key_id'])" "$CONFIG")
    ISSUER=$(/usr/bin/python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['issuer_id'])" "$CONFIG")
    KEY_PATH=$(/usr/bin/python3 -c "import json,os,sys; print(os.path.expanduser(json.load(open(sys.argv[1]))['key_path']))" "$CONFIG")
    echo "Notarizing (usually a few minutes)…"
    xcrun notarytool submit "$DMG" --key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$ISSUER" --wait --timeout 1h \
        | tee "$BUILD/notary.log"
    grep -q "status: Accepted" "$BUILD/notary.log" || {
        ID=$(grep -m1 -E "^\s*id:" "$BUILD/notary.log" | awk '{print $2}')
        echo "Notarization failed; Apple's log:" >&2
        xcrun notarytool log "$ID" --key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$ISSUER" >&2 || true
        exit 1
    }
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    # What a downloaded copy gets: Gatekeeper must accept the DMG and the app as notarized Developer ID software.
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
    spctl --assess --type execute --verbose=2 "$PRODUCT"
fi

echo "Architectures: $(lipo -archs "$PRODUCT/Contents/MacOS/1Cleaner")"
echo "DMG: $DMG ($(du -h "$DMG" | cut -f1))"
