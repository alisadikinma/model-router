#!/usr/bin/env bash
# Phase G test: install.sh symlinks config + bins + hook into a (temp) HOME.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$DIR/tests/assert.sh"

[[ -x "$DIR/install.sh" ]] || fail "install.sh not found"
TMPH="$(mktemp -d)"; trap 'rm -rf "$TMPH"' EXIT

HOME="$TMPH" bash "$DIR/install.sh" >/dev/null

[[ -L "$TMPH/.config/model-router/router.config.jsonc" ]] || fail "config symlink missing"
[[ -L "$TMPH/.local/bin/route" ]]                          || fail "route symlink missing"
[[ -L "$TMPH/.local/bin/router-doctor" ]]                  || fail "router-doctor symlink missing"
[[ -L "$TMPH/.local/bin/gx" ]]                             || fail "gx symlink missing"
[[ -L "$TMPH/.claude/hooks/delegate.sh" ]]                 || fail "hook symlink missing"
echo "ok: all symlinks created"

echo "test_install: PASS"
