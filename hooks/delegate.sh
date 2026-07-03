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
    f"JALAN A AUTO-DELEGATE — CHAIN OF COMMAND (active executor: {m}): hand the WHOLE task to the "
    f"executor, do NOT micro-manage per-step. Write ONE whole-task spec + hard gate (implement + "
    f"write & RUN tests to green, no placeholder, DON'T commit), then TERIMA-BERES: review the "
    f"finished diff wholesale + commit. Three tiers — Opus (you) = strategy (brainstorm/plan/review/"
    f"debug + commit gate); GLM-5.2 (ollama) = execution LEAD / right hand: the autonomous "
    f"`opencode run -m ollama/glm-5.2:cloud` that OWNS execution, supervises + fixes deepseek's "
    f"output, takes the hard/long-context/critical slices (migration/auth/threshold) directly, "
    f"iterates tests to green; deepseek-v4-pro (opencode-go) = bulk labor (cheap first-draft "
    f"codegen + mechanical mass edits, flash `{mech}` for pure rename/i18n). INVARIANT: "
    f"GLM-5.2 -> ollama ONLY, deepseek -> opencode-go ONLY, never cross. STAY on Claude (never "
    f"delegate): the 4 judgment skills (brainstorm/plan/review/debug) + commit. Test authoring + "
    f"CRITICAL files (auth/migration/money/threshold) now go to the executor too — the guardrail is "
    f"that YOU REVIEW them harder, not that you type them. `gx <spec>.md` (edit-only, {m}) stays "
    f"fine for a bounded single-file mechanical edit; the per-step write-test->gx->review LOOP "
    f"across a multi-phase plan is the ANTI-PATTERN (2x tokens). Gotcha: spec + targets INSIDE the "
    f"repo; run from repo root."
)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": ctx}}))
PY
