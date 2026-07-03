#!/usr/bin/env bash
# model-router installer — symlinks config + bins + delegate hook into $HOME. Idempotent.
# Backs up any real file it would replace (as *.bak.$$). Respects $HOME (tests override it).
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CFG_DIR="$HOME/.config/model-router"
BIN_DIR="$HOME/.local/bin"
HOOK_DIR="$HOME/.claude/hooks"
mkdir -p "$CFG_DIR" "$BIN_DIR" "$HOOK_DIR"

link() { # src dst — back up a real (non-symlink) file, then symlink
  local s="$1" d="$2"
  if [[ -e "$d" && ! -L "$d" ]]; then mv "$d" "$d.bak.$$"; echo "backed up $d → $d.bak.$$"; fi
  ln -sfn "$s" "$d"; echo "linked $d"
}

link "$SRC/router.config.jsonc" "$CFG_DIR/router.config.jsonc"
link "$SRC/bin/route"           "$BIN_DIR/route"
link "$SRC/bin/router-doctor"   "$BIN_DIR/router-doctor"
link "$SRC/bin/gx"              "$BIN_DIR/gx"
link "$SRC/hooks/delegate.sh"      "$HOOK_DIR/delegate.sh"
link "$SRC/hooks/code-delegate.sh" "$HOOK_DIR/code-delegate.sh"

# if an old gaspol delegate hook is already registered (settings.json points at it), repoint
# it to the new state-aware logic so the registration keeps working with no settings.json edit.
OLD="$HOOK_DIR/gaspol-opencode-delegate.sh"
if [[ -e "$OLD" && ! -L "$OLD" ]]; then
  mv "$OLD" "$OLD.bak.$$"; echo "backed up old gaspol hook → $OLD.bak.$$"
  ln -sfn "$SRC/hooks/delegate.sh" "$OLD"; echo "repointed registered gaspol hook → new delegate.sh"
fi

echo "install done. next: route default && router-doctor"
