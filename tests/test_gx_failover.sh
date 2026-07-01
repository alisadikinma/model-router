#!/usr/bin/env bash
# Phase D test: gx auto-failover. opencode-go failure -> retry once on ollama/glm-5.2:cloud.
# An already-ollama failure must NOT re-failover (no loop).
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$DIR/tests/assert.sh"

GX="$HOME/.local/bin/gx"
[[ -x "$GX" ]] || fail "gx not found"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export OPENCODE_LOG="$TMP/calls.log"
export ROUTER_STATE="$TMP/state"
echo "dummy spec" > "$TMP/spec.md"

# stub opencode: log -m model; fail if opencode-go, else succeed
cat > "$TMP/opencode" <<'EOF'
#!/usr/bin/env bash
m=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-m" ]] && m="$2"; shift; done
echo "$m" >> "$OPENCODE_LOG"
[[ "$m" == *opencode-go* ]] && { echo "error: quota exceeded" >&2; exit 1; }
exit 0
EOF
chmod +x "$TMP/opencode"

: > "$OPENCODE_LOG"
echo "opencode-go/deepseek-v4-pro" > "$ROUTER_STATE"
out="$(cd "$DIR" && PATH="$TMP:$PATH" "$GX" "$TMP/spec.md" 2>&1 || true)"
assert_contains "$out" "failover" "logs failover on opencode failure"
assert_eq "2" "$(grep -c . "$OPENCODE_LOG")" "opencode retried once (2 calls)"
assert_contains "$(cat "$OPENCODE_LOG")" "ollama/glm-5.2:cloud" "retry used ollama glm"

# guard: already-ollama failure must NOT re-failover
cat > "$TMP/opencode" <<'EOF'
#!/usr/bin/env bash
m=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-m" ]] && m="$2"; shift; done
echo "$m" >> "$OPENCODE_LOG"; echo "error: fail" >&2; exit 1
EOF
chmod +x "$TMP/opencode"
: > "$OPENCODE_LOG"
echo "ollama/glm-5.2:cloud" > "$ROUTER_STATE"
(cd "$DIR" && PATH="$TMP:$PATH" "$GX" "$TMP/spec.md" >/dev/null 2>&1 || true)
assert_eq "1" "$(grep -c . "$OPENCODE_LOG")" "ollama failure does NOT re-failover (no loop)"

echo "test_gx_failover: PASS"
