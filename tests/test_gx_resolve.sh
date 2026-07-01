#!/usr/bin/env bash
# Phase C test: gx model resolution precedence -m > GX_MODEL > state-file > default.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$DIR/tests/assert.sh"

GX="$HOME/.local/bin/gx"
[[ -x "$GX" ]] || fail "gx not found at $GX"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export ROUTER_STATE="$TMP/state"

echo "ollama/glm-5.2:cloud" > "$ROUTER_STATE"
assert_eq "ollama/glm-5.2:cloud"        "$(env -u GX_MODEL "$GX" --print-model)"            "state-file resolution"
assert_eq "envmodel"                    "$(GX_MODEL=envmodel "$GX" --print-model)"          "GX_MODEL over state"
assert_eq "flagmodel"                   "$(GX_MODEL=envmodel "$GX" -m flagmodel --print-model)" "-m over env+state"

rm -f "$ROUTER_STATE"
assert_eq "opencode-go/deepseek-v4-pro" "$(env -u GX_MODEL "$GX" --print-model)"            "default fallback"

echo "test_gx_resolve: PASS"
