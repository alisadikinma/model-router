#!/usr/bin/env bash
# Phase G test: `route panic` prints the ollama-GLM emergency-brain command, print-only.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$DIR/tests/assert.sh"

export ROUTER_CONFIG="$DIR/router.config.jsonc"
R="$DIR/bin/route"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

out="$("$R" panic)"
assert_contains     "$out" "opencode run -m ollama/glm-5.2:cloud" "panic prints ollama-GLM brain cmd"
assert_not_contains "$out" "opencode-go/glm"                       "panic respects invariant (no opencode-go glm)"

# print-only: must NOT exec opencode. Stub that leaves a marker if run.
printf '#!/usr/bin/env bash\ntouch "%s/ran"\n' "$TMP" > "$TMP/opencode"
chmod +x "$TMP/opencode"
PATH="$TMP:$PATH" "$R" panic >/dev/null
[[ ! -f "$TMP/ran" ]] || fail "panic (no --run) must not exec opencode"
echo "ok: panic is print-only without --run"

echo "test_panic: PASS"
