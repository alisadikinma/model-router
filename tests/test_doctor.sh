#!/usr/bin/env bash
# Phase F test: router-doctor --json emits opencode_auth, ollama_signin, models[].
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$DIR/tests/assert.sh"

D="$DIR/bin/router-doctor"
[[ -x "$D" ]] || fail "bin/router-doctor not found"

out="$("$D" --json)"
echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert 'opencode_auth' in d
assert 'ollama_signin' in d
assert isinstance(d['models'], list)
print('doctor-json-ok')
" || fail "doctor --json missing keys"
echo "test_doctor: PASS"
