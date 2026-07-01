#!/usr/bin/env bash
# model-router delegate hook — PreToolUse on the Skill tool.
# When gaspol-execute / gaspol-parallel fires, inject the JALAN-A directive naming the
# ACTIVE executor model (from router state). Generalizes the old hardcoded-deepseek hook.
# ponytail: python3 emits the JSON (correct escaping) — never hand-format a directive string.
set -euo pipefail

STATE="${ROUTER_STATE:-$HOME/.config/model-router/state}"
if [[ -s "$STATE" ]]; then MODEL="$(<"$STATE")"; MODEL="${MODEL//[$'\n\r']/}"; else MODEL="opencode-go/deepseek-v4-pro"; fi

INPUT="$(cat)"
SKILL="$(printf '%s' "$INPUT" | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('tool_input',{}).get('skill',''))
except Exception: print('')" 2>/dev/null || true)"

case "$SKILL" in
  gaspol-execute|gaspol-parallel|*:gaspol-execute|*:gaspol-parallel) ;;  # bare or namespaced only
  *) exit 0 ;;   # not our skill -> no-op passthrough
esac

MODEL="$MODEL" python3 <<'PY'
import json, os
m = os.environ["MODEL"]
mech = "opencode-go/deepseek-v4-flash"
ctx = (
    f"JALAN A AUTO-DELEGATE (active executor: {m}): for the IMPLEMENT / bulk-codegen step of every "
    f"phase, do NOT edit source files yourself — write the phase spec to an in-repo `.md` and run "
    f"`gx <spec>.md` (resolves to {m} via router state). Mechanical mass-edits "
    f"(rename/type-hint/i18n/import) -> `gx <spec>.md -m {mech}`. gx auto-failovers a dead opencode "
    f"pool to ollama/glm-5.2:cloud. STAY on Claude (never delegate): plan/design, writing tests, "
    f"review, verify, and the commit. For gaspol-parallel, each implementer subagent edits via `gx` "
    f"on its own file-isolated lane spec. Gotcha: spec file AND targets must be INSIDE the repo; run "
    f"`gx` from repo root. CRITICAL/auth/migration/money/threshold logic + test authoring = Claude self, never gx."
)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": ctx}}))
PY
