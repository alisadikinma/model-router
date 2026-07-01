#!/usr/bin/env bash
# Phase B test: route writes correct executor model to state; bad profile fails.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$DIR/tests/assert.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export ROUTER_CONFIG="$DIR/router.config.jsonc"
export ROUTER_STATE="$TMP/state"
R="$DIR/bin/route"
[[ -x "$R" ]] || fail "bin/route not found or not executable"

"$R" glm-heavy >/dev/null
assert_eq "ollama/glm-5.2:cloud"        "$(cat "$TMP/state")" "glm-heavy -> state"
"$R" default >/dev/null
assert_eq "opencode-go/deepseek-v4-pro" "$(cat "$TMP/state")" "default -> state"
"$R" mechanical >/dev/null
assert_eq "opencode-go/deepseek-v4-flash" "$(cat "$TMP/state")" "mechanical -> state"

if "$R" bogus >/dev/null 2>&1; then fail "unknown profile should exit non-zero"; fi
echo "ok: unknown profile exits non-zero"

out="$("$R")"
assert_contains "$out" "opencode-go/deepseek-v4-flash" "no-arg shows active model"
echo "test_route: PASS"
