#!/bin/bash
# Usage: check-archive.sh <path/to/Stark.xcarchive>
# Fails (non-zero, clear message) when the archived watch app or its widget would ship without
# the watch App Group or the Info.plist keys watchOS needs. Signing problems are silent otherwise:
# the build succeeds and the app just cannot share data or never installs on the watch.
#
# Entitlements are read with `codesign -d --entitlements - --xml <bundle>`: the XML form prints the
# plist on stdout (the "Executable=" line goes to stderr), the same on current and older macOS.
set -euo pipefail

ARCHIVE="${1:?usage: check-archive.sh <path to Stark.xcarchive>}"
WATCH_GROUP="group.com.caritos.todo-txt.watch"
PHONE_BUNDLE_ID="com.caritos.todo-txt"
WATCH_APP="$ARCHIVE/Products/Applications/Stark.app/Watch/StarkWatch.app"
WIDGET="$WATCH_APP/PlugIns/StarkWatchWidget.appex"

fail() { echo "error: $*" >&2; exit 1; }

[ -d "$WATCH_APP" ] || fail "the archive has no Watch/StarkWatch.app inside Stark.app"
[ -d "$WIDGET" ] || fail "StarkWatch.app has no PlugIns/StarkWatchWidget.appex"

# Entitlements: the signed bundle must carry the watch App Group.
for bundle in "$WATCH_APP" "$WIDGET"; do
  name="$(basename "$bundle")"
  ents="$(codesign -d --entitlements - --xml "$bundle" 2>/dev/null)" \
    || fail "cannot read the entitlements of $name (is it signed?)"
  grep -q -F "$WATCH_GROUP" <<<"$ents" \
    || fail "$name is signed without the App Group $WATCH_GROUP (profile missing the group?)"
done

# Watch app Info.plist: a companion-linked watch app, not watch-only.
watch_plist="$(plutil -p "$WATCH_APP/Info.plist")" || fail "cannot read StarkWatch.app/Info.plist"
grep -q '"WKApplication" => true' <<<"$watch_plist" \
  || fail "StarkWatch.app Info.plist has no WKApplication = true"
grep -q "\"WKCompanionAppBundleIdentifier\" => \"$PHONE_BUNDLE_ID\"" <<<"$watch_plist" \
  || fail "StarkWatch.app Info.plist WKCompanionAppBundleIdentifier is not $PHONE_BUNDLE_ID"
if grep -q '"WKWatchOnly"' <<<"$watch_plist"; then
  fail "StarkWatch.app Info.plist has WKWatchOnly (it is a companion app)"
fi

# Widget Info.plist: a WidgetKit extension.
widget_plist="$(plutil -p "$WIDGET/Info.plist")" || fail "cannot read StarkWatchWidget.appex/Info.plist"
grep -q '"NSExtension"' <<<"$widget_plist" \
  || fail "StarkWatchWidget.appex Info.plist has no NSExtension"
grep -q 'com.apple.widgetkit-extension' <<<"$widget_plist" \
  || fail "StarkWatchWidget.appex NSExtension is not com.apple.widgetkit-extension"

echo "==> Archive check passed: watch app and widget carry $WATCH_GROUP and the right Info.plist keys"
