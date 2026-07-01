#!/usr/bin/env bash
# Phase E test: delegate hook emits valid JSON naming the active executor model;
# non-matching skill is a no-op.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$DIR/tests/assert.sh"

H="$DIR/hooks/delegate.sh"
[[ -x "$H" ]] || fail "hooks/delegate.sh not found"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export ROUTER_STATE="$TMP/state"

echo "ollama/glm-5.2:cloud" > "$ROUTER_STATE"
out="$(printf '{"tool_input":{"skill":"gaspol-dev:gaspol-execute"}}' | "$H")"
echo "$out" | python3 -c "import json,sys; json.load(sys.stdin)" || fail "stdout not valid JSON"
assert_contains "$out" "ollama/glm-5.2:cloud" "directive names active model"
assert_contains "$out" "additionalContext"    "has additionalContext"

rm -f "$ROUTER_STATE"
out2="$(printf '{"tool_input":{"skill":"gaspol-dev:gaspol-parallel"}}' | "$H")"
assert_contains "$out2" "opencode-go/deepseek-v4-pro" "default model when no state"

out3="$(printf '{"tool_input":{"skill":"something-else"}}' | "$H")"
assert_eq "" "$out3" "non-matching skill -> no-op"

echo "test_hook: PASS"
