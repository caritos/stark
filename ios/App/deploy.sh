#!/bin/bash
# Builds Stark and installs + launches it on a connected physical
# iPhone, entirely via CLI (xcodebuild + xcrun devicectl) - no Xcode GUI needed.
#
# Usage: ./deploy.sh [device name substring]

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/Stark" && pwd)"
DEFAULT_DEVICE_NAME="Eladios-iPhone-16-Plus"
DEVICE_NAME="${1:-$DEFAULT_DEVICE_NAME}"

cd "$PROJECT_DIR"

echo "==> Finding device matching '$DEVICE_NAME'..."
DEVICE_ID=$( (xcrun devicectl list devices 2>/dev/null \
  | grep -v unavailable \
  | grep -F "$DEVICE_NAME" \
  | awk -v host="$DEVICE_NAME" '{for(i=1;i<=NF;i++) if(index($i, host) > 0) {print $(i+1); exit}}' \
  | head -1) || true)

if [ -z "$DEVICE_ID" ]; then
  echo "error: no connected device found matching '$DEVICE_NAME'" >&2
  echo "Connected devices:" >&2
  xcrun devicectl list devices >&2
  exit 1
fi
echo "    -> device id: $DEVICE_ID"

echo "==> Building (xcodebuild)..."
xcodebuild -project Stark.xcodeproj \
  -scheme Stark \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -allowProvisioningUpdates \
  build

APP_PATH=$(xcodebuild -project Stark.xcodeproj \
  -scheme Stark \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{bpd=$2} / FULL_PRODUCT_NAME =/{fpn=$2} END{print bpd"/"fpn}')

echo "==> Installing on device..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

BUNDLE_ID=$(defaults read "$APP_PATH/Info" CFBundleIdentifier)

echo "==> Launching..."
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"

echo "==> Done. $BUNDLE_ID is running on $DEVICE_NAME."
