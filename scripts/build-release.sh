#!/usr/bin/env bash
# Builds, signs (Developer ID), notarizes and staples Promo Studio and packages
# it as a DMG for GitHub Releases / Homebrew. See docs/RELEASE.md.
#
# Requirements:
#   * Xcode and XcodeGen (brew install xcodegen)
#   * a "Developer ID Application" certificate of $TEAM_ID in the login keychain
#   * dmgbuild for the designed DMG window: `pipx install dmgbuild`
#   * notarytool credentials stored once with:
#       xcrun notarytool store-credentials promo-studio-notary \
#         --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>
#     (or set NOTARY_PROFILE to another stored profile)
#
# Output: dist/PromoStudio-<version>.dmg (+ .sha256)
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID="${TEAM_ID:-5JMD3VSD7N}"
NOTARY_PROFILE="${NOTARY_PROFILE:-promo-studio-notary}"
VERSION="${VERSION:-$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*"([^"]+)".*/\1/')}"
BUILD="build/release"
DIST="dist"
ARCHIVE="$BUILD/PromoStudio.xcarchive"
EXPORT="$BUILD/export"
APP="$EXPORT/Promo Studio.app"
DMG="$DIST/PromoStudio-$VERSION.dmg"

DMGBUILD="${DMGBUILD:-$(command -v dmgbuild || true)}"
if [[ -z "$DMGBUILD" && "${ALLOW_PLAIN_DMG:-0}" != "1" ]]; then
  # A release DMG without its designed window is a mistake, not a fallback.
  echo "dmgbuild not found. Install it (pipx install dmgbuild) or point DMGBUILD at it;" >&2
  echo "ALLOW_PLAIN_DMG=1 builds a plain DMG for local testing." >&2
  exit 1
fi
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || {
  echo "No notarytool credentials named \"$NOTARY_PROFILE\". Store them first (see the header of this script)" >&2
  echo "or set NOTARY_PROFILE to an existing profile." >&2
  exit 1
}

rm -rf "$BUILD" && mkdir -p "$BUILD" "$DIST"
xcodegen generate --quiet

echo "▸ Archiving Promo Studio $VERSION"
xcodebuild archive \
  -project PromoStudio.xcodeproj -scheme PromoStudio -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  MARKETING_VERSION="$VERSION" \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application"

echo "▸ Exporting with Developer ID"
sed "s/__TEAM_ID__/$TEAM_ID/" scripts/export/ExportOptions.plist > "$BUILD/ExportOptions.plist"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$BUILD/ExportOptions.plist" \
  -exportPath "$EXPORT"

echo "▸ Verifying the signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --display --verbose=2 "$APP" 2>&1 | grep -E "Authority=Developer ID|TeamIdentifier=$TEAM_ID|flags=.*runtime"
test -d "$APP/Contents/Resources/RemotionTemplate"

echo "▸ Notarizing the app"
ditto -c -k --keepParent "$APP" "$BUILD/PromoStudio.zip"
xcrun notarytool submit "$BUILD/PromoStudio.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

echo "▸ Building the DMG"
rm -f "$DMG"
if [[ -n "$DMGBUILD" ]]; then
  # Designed window: background, icon positions (scripts/dmg/settings.py).
  "$DMGBUILD" -s scripts/dmg/settings.py -D app="$APP" "Promo Studio" "$DMG"
else
  echo "  ALLOW_PLAIN_DMG=1 — building a plain DMG without the designed window"
  STAGING="$BUILD/dmg"
  mkdir -p "$STAGING"
  cp -R "$APP" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "Promo Studio" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"
fi
codesign --sign "Developer ID Application" --timestamp "$DMG"

echo "▸ Notarizing the DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" | tee "$(basename "$DMG").sha256")

echo "✔ $DMG"
echo "Next: scripts/prepare-release.sh $VERSION"
