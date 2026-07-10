#!/usr/bin/env bash
# model-router installer — symlinks config + bins + delegate hook into $HOME. Idempotent.
# Backs up any real file it would replace (as *.bak.$$). Respects $HOME (tests override it).
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CFG_DIR="$HOME/.config/model-router"
BIN_DIR="$HOME/.local/bin"
HOOK_DIR="$HOME/.claude/hooks"
OC_DIR="$HOME/.config/opencode"
mkdir -p "$CFG_DIR" "$BIN_DIR" "$HOOK_DIR" "$OC_DIR"

link() { # src dst — back up a real (non-symlink) file, then symlink
  local s="$1" d="$2"
  if [[ -e "$d" && ! -L "$d" ]]; then mv "$d" "$d.bak.$$"; echo "backed up $d → $d.bak.$$"; fi
  ln -sfn "$s" "$d"; echo "linked $d"
}

link "$SRC/router.config.jsonc" "$CFG_DIR/router.config.jsonc"
link "$SRC/bin/route"           "$BIN_DIR/route"
link "$SRC/bin/router-doctor"   "$BIN_DIR/router-doctor"
link "$SRC/bin/gx"              "$BIN_DIR/gx"
link "$SRC/bin/oc-stream"       "$BIN_DIR/oc-stream"
link "$SRC/hooks/delegate.sh"      "$HOOK_DIR/delegate.sh"
link "$SRC/hooks/code-delegate.sh" "$HOOK_DIR/code-delegate.sh"
link "$SRC/hooks/session-mode.sh"  "$HOOK_DIR/session-mode.sh"
link "$SRC/opencode.jsonc"         "$OC_DIR/opencode.jsonc"
link "$SRC/opencode.AGENTS.md"     "$OC_DIR/AGENTS.md"

# shell bridge: source the gaspol-executor selector so gaspol-dev Option 4 sees $GASPOL_EXECUTOR
# (idempotent — only appends the source line once). Env vars can't be symlinked, so this is the
# one profile edit the installer makes.
ZSHRC="$HOME/.zshrc"
if [[ -f "$ZSHRC" ]] && ! grep -qF "shell/gaspol-executor.sh" "$ZSHRC"; then
  printf '\nsource "%s/shell/gaspol-executor.sh"  # model-router: gaspol-dev Option 4 bridge\n' "$SRC" >> "$ZSHRC"
  echo "added gaspol-executor source to $ZSHRC"
fi

# if an old gaspol delegate hook is already registered (settings.json points at it), repoint
# it to the new state-aware logic so the registration keeps working with no settings.json edit.
OLD="$HOOK_DIR/gaspol-opencode-delegate.sh"
if [[ -e "$OLD" && ! -L "$OLD" ]]; then
  mv "$OLD" "$OLD.bak.$$"; echo "backed up old gaspol hook → $OLD.bak.$$"
  ln -sfn "$SRC/hooks/delegate.sh" "$OLD"; echo "repointed registered gaspol hook → new delegate.sh"
fi

echo "install done. next: route default && router-doctor"
cat <<'SNIP'

To enable the session-start mode popup, add this SessionStart hook to your Claude Code
settings.json (the installer does NOT edit settings.json — paste it yourself):

  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/session-mode.sh" } ] }
    ]
  }
SNIP
