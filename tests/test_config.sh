#!/usr/bin/env bash
# Phase A test: router.config.jsonc parses + has required keys.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$DIR/tests/assert.sh"

CFG="$DIR/router.config.jsonc"
[[ -f "$CFG" ]] || fail "router.config.jsonc not found"

j() { python3 "$DIR/lib/jsonc.py" "$CFG" "$1"; }

assert_eq "opencode-go/deepseek-v4-pro" "$(j profiles.default)"        "profiles.default"
assert_eq "opencode-go/deepseek-v4-pro" "$(j tiers.workhorse.model)"   "tiers.workhorse.model"
assert_eq "ollama/glm-5.2:cloud"        "$(j tiers.heavy.model)"       "tiers.heavy.model"

for p in default glm-heavy mechanical failover-opencode offline; do
  j "profiles.$p" >/dev/null 2>&1 || fail "missing profile: $p"
done
echo "ok: all 5 profiles present"
echo "test_config: PASS"
