#!/bin/bash
# Builds the stark-claude CLI (release) and symlinks it to ~/.local/bin/stark-claude.
#
# Usage: ios/scripts/install-stark-claude.sh

set -euo pipefail
# /usr/bin first: Homebrew tools earlier on PATH can break Apple's toolchain.
export PATH="/usr/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LINK_DIR="$HOME/.local/bin"
LINK="$LINK_DIR/stark-claude"
SWIFT="${SWIFT:-swift}"  # overridable so the test can use a fake

cd "$IOS_DIR"
echo "==> Building stark-claude (release)..."
"$SWIFT" build -c release --product stark-claude
BIN_DIR="$("$SWIFT" build -c release --show-bin-path)"
BIN="$BIN_DIR/stark-claude"
if [ ! -x "$BIN" ]; then
  echo "error: build finished but $BIN was not found" >&2
  exit 1
fi

mkdir -p "$LINK_DIR"
if [ -e "$LINK" ] || [ -L "$LINK" ]; then
  if [ ! -L "$LINK" ]; then
    echo "error: $LINK exists and is not a symlink; refusing to overwrite it" >&2
    exit 1
  fi
fi
ln -sfn "$BIN" "$LINK"
echo "==> Linked $LINK -> $BIN"

case ":$PATH:" in
  *":$LINK_DIR:"*) ;;
  *) echo "warning: $LINK_DIR is not on your PATH; add it to your shell profile to run 'stark-claude' directly" >&2 ;;
esac
echo "Next: run 'stark-claude pair' (secret from Stark > Settings > Claude Code)."
