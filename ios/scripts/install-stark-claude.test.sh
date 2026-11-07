#!/bin/bash
# Test for install-stark-claude.sh: a fake `swift` and a temp HOME, no real build.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/install-stark-claude.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home"
cat > "$T/bin/swift" <<'SW'
#!/bin/bash
# fake: `swift build -c release --product stark-claude`, then `--show-bin-path`
if [[ "$*" == *"--show-bin-path"* ]]; then echo "$FAKE_BIN_DIR"; exit 0; fi
mkdir -p "$FAKE_BIN_DIR"; printf '#!/bin/sh\necho fake\n' > "$FAKE_BIN_DIR/stark-claude"; chmod +x "$FAKE_BIN_DIR/stark-claude"
SW
chmod +x "$T/bin/swift"
export FAKE_BIN_DIR="$T/build/release"
run() { HOME="$T/home" SWIFT="$T/bin/swift" PATH="$T/bin:/usr/bin:/bin" bash "$SCRIPT" 2>&1; }
fail() { echo "FAIL: $*" >&2; exit 1; }

out=$(run) || fail "first run exited non-zero: $out"
L="$T/home/.local/bin/stark-claude"
[ -L "$L" ] || fail "symlink not created"
[ "$(readlink "$L")" = "$FAKE_BIN_DIR/stark-claude" ] || fail "symlink target wrong"
echo "$out" | grep -q "not on your PATH" || fail "no PATH warning"

out=$(run) || fail "re-run exited non-zero: $out"
[ "$(readlink "$L")" = "$FAKE_BIN_DIR/stark-claude" ] || fail "re-run changed link"

rm "$L"; echo "mine" > "$L"
if out=$(run); then fail "overwrote a regular file"; fi
echo "$out" | grep -q "not a symlink" || fail "no refusal message: $out"
[ "$(cat "$L")" = "mine" ] || fail "regular file was modified"
echo "PASS"
