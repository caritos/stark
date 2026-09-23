#!/bin/bash
# Archives, exports, and uploads Stark to App Store Connect (TestFlight) - entirely via
# CLI (xcodebuild + an App Store Connect API key), no Xcode GUI or Apple ID login needed.
#
# One-time setup: generate an App Store Connect API key at
# appstoreconnect.apple.com -> Users and Access -> Integrations -> App Store Connect API
# (role App Manager or Admin), download its .p8 ONCE, and save it as
# ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8.
#
# Deliberately does NOT submit the uploaded build for App Store review - it only lands
# in TestFlight.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/Stark"
BUILD_DIR="/tmp/stark-ship-build"

API_KEY_ID="${API_KEY_ID:?set API_KEY_ID to your App Store Connect API key ID}"
API_ISSUER_ID="${API_ISSUER_ID:?set API_ISSUER_ID to your App Store Connect issuer ID}"
API_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${API_KEY_ID}.p8"

if [ ! -f "$API_KEY_PATH" ]; then
  echo "error: App Store Connect API key not found at $API_KEY_PATH" >&2
  exit 1
fi

cd "$PROJECT_DIR"
PBXPROJ="Stark.xcodeproj/project.pbxproj"

MARKETING_VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$PBXPROJ" | head -1)
CURRENT_BUILD=$(sed -n 's/.*CURRENT_PROJECT_VERSION = \(.*\);/\1/p' "$PBXPROJ" | head -1)
NEXT_BUILD=$((CURRENT_BUILD + 1))

# MARKETING_VERSION is MAJOR.MINOR.PATCH - bump PATCH on every ship, same as
# the build-number counter below. App Store Connect rejects an upload whose
# version isn't strictly greater than the current live one.
IFS='.' read -r MV_MAJOR MV_MINOR MV_PATCH <<< "$MARKETING_VERSION"
NEXT_MARKETING_VERSION="${MV_MAJOR}.${MV_MINOR}.$((MV_PATCH + 1))"

ARCHIVE_PATH="$BUILD_DIR/Stark.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

export PATH="/usr/bin:$PATH"

# The new version/build number are passed as xcodebuild overrides, not written into
# project.pbxproj yet - so a failed archive or export (set -e exits immediately) leaves
# the working tree untouched instead of stuck with an uncommitted, never-shipped bump.
echo "==> Archiving version $NEXT_MARKETING_VERSION (build $NEXT_BUILD)..."
xcodebuild archive \
  -project Stark.xcodeproj \
  -scheme Stark \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$API_KEY_PATH" \
  -authenticationKeyID "$API_KEY_ID" \
  -authenticationKeyIssuerID "$API_ISSUER_ID" \
  MARKETING_VERSION="$NEXT_MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$NEXT_BUILD"

echo "==> Exporting and uploading to App Store Connect..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$SCRIPT_DIR/ExportOptions.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$API_KEY_PATH" \
  -authenticationKeyID "$API_KEY_ID" \
  -authenticationKeyIssuerID "$API_ISSUER_ID"

# Only now, after a successful archive AND export, persist the bump to the checked-in
# project file - recording what was actually shipped, not what was merely attempted.
echo "==> Recording shipped version $NEXT_MARKETING_VERSION (build $NEXT_BUILD) in project.pbxproj"
sed -i '' "s/MARKETING_VERSION = $MARKETING_VERSION;/MARKETING_VERSION = $NEXT_MARKETING_VERSION;/g" "$PBXPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = $CURRENT_BUILD;/CURRENT_PROJECT_VERSION = $NEXT_BUILD;/g" "$PBXPROJ"

echo ""
echo "Done. Shipped v$NEXT_MARKETING_VERSION (build $NEXT_BUILD) to App Store Connect."
echo "Check TestFlight processing status at appstoreconnect.apple.com."
