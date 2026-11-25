#!/bin/bash
# Tests check-archive.sh against fake .xcarchive trees: real plists (plutil) and a fake `codesign`
# shim on PATH that prints the entitlements stored next to each bundle (entitlements.xml).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-archive.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
GROUP="group.com.caritos.todo-txt.watch"
fails=0

mkdir -p "$TMP/bin"
cat > "$TMP/bin/codesign" <<'SH'
#!/bin/bash
# usage: codesign -d --entitlements - [--xml] <bundle>
for last; do :; done
cat "$last/entitlements.xml" 2>/dev/null
echo "Executable=$last/x" >&2
SH
chmod +x "$TMP/bin/codesign"

ent() { # bundle [group]
  if [ -n "${2:-}" ]; then
    printf '<?xml version="1.0"?><plist><dict><key>com.apple.security.application-groups</key><array><string>%s</string></array></dict></plist>' "$2" > "$1/entitlements.xml"
  else
    printf '<?xml version="1.0"?><plist><dict><key>get-task-allow</key><true/></dict></plist>' > "$1/entitlements.xml"
  fi
}
plist() { plutil -create xml1 "$1"; }

make_good() { # dir
  local a="$1"
  local w="$a/Products/Applications/Stark.app/Watch/StarkWatch.app"
  local x="$w/PlugIns/StarkWatchWidget.appex"
  mkdir -p "$x"
  plist "$w/Info.plist"
  plutil -insert WKApplication -bool true "$w/Info.plist"
  plutil -insert WKCompanionAppBundleIdentifier -string com.caritos.todo-txt "$w/Info.plist"
  plist "$x/Info.plist"
  plutil -insert NSExtension -json '{"NSExtensionPointIdentifier":"com.apple.widgetkit-extension"}' "$x/Info.plist"
  ent "$w" "$GROUP"; ent "$x" "$GROUP"
}

expect() { # name want(0|1) archive [needle]
  local out rc
  out="$(PATH="$TMP/bin:$PATH" bash "$CHECK" "$3" 2>&1)"; rc=$?
  local ok=1
  if [ "$2" = 0 ] && [ $rc -ne 0 ]; then ok=0; fi
  if [ "$2" = 1 ] && [ $rc -eq 0 ]; then ok=0; fi
  if [ -n "${4:-}" ] && ! grep -q -- "$4" <<<"$out"; then ok=0; fi
  if [ $ok = 1 ]; then echo "ok   $1"; else echo "FAIL $1 (rc=$rc): $out"; fails=$((fails+1)); fi
}

W() { echo "$1/Products/Applications/Stark.app/Watch/StarkWatch.app"; }
X() { echo "$(W "$1")/PlugIns/StarkWatchWidget.appex"; }

A="$TMP/good.xcarchive"; make_good "$A"
expect "all good passes" 0 "$A"

A="$TMP/nogroup-app.xcarchive"; make_good "$A"; ent "$(W "$A")"
expect "watch app without the App Group fails" 1 "$A" "StarkWatch.app"

A="$TMP/nogroup-appex.xcarchive"; make_good "$A"; ent "$(X "$A")"
expect "watch widget without the App Group fails" 1 "$A" "StarkWatchWidget.appex"

A="$TMP/nowkapp.xcarchive"; make_good "$A"; plutil -remove WKApplication "$(W "$A")/Info.plist"
expect "missing WKApplication fails" 1 "$A" "WKApplication"

A="$TMP/wrongcompanion.xcarchive"; make_good "$A"; plutil -replace WKCompanionAppBundleIdentifier -string com.other "$(W "$A")/Info.plist"
expect "wrong WKCompanionAppBundleIdentifier fails" 1 "$A" "WKCompanionAppBundleIdentifier"

A="$TMP/watchonly.xcarchive"; make_good "$A"; plutil -insert WKWatchOnly -bool true "$(W "$A")/Info.plist"
expect "WKWatchOnly present fails" 1 "$A" "WKWatchOnly"

A="$TMP/noext.xcarchive"; make_good "$A"; plutil -remove NSExtension "$(X "$A")/Info.plist"
expect "widget without NSExtension fails" 1 "$A" "NSExtension"

A="$TMP/noappex.xcarchive"; make_good "$A"; rm -rf "$(X "$A")"
expect "missing appex fails" 1 "$A" "StarkWatchWidget.appex"

A="$TMP/nowatch.xcarchive"; make_good "$A"; rm -rf "$(W "$A")"
expect "missing watch app fails" 1 "$A" "StarkWatch.app"

[ $fails = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
