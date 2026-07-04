#!/usr/bin/env bash
# model-router delegate hook — PreToolUse on the Skill tool.
# When gaspol-execute / gaspol-parallel fires, inject the JALAN-A directive to launch the
# TWO-TIER executor (`gx --team`): a GLM-5.2 lead delegates coding to the deepseek @coder
# subagent in one opencode task. No `route glm-heavy` (the two-tier models live in the agent
# config, not router state) — this hook only nudges Claude to use the right entry point.
# ponytail: python3 emits the JSON (correct escaping) — never hand-format a directive string.
set -euo pipefail

INPUT="$(cat)"
SKILL="$(printf '%s' "$INPUT" | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('tool_input',{}).get('skill',''))
except Exception: print('')" 2>/dev/null || true)"

case "$SKILL" in
  gaspol-execute|gaspol-parallel|*:gaspol-execute|*:gaspol-parallel) ;;  # bare or namespaced only
  *) exit 0 ;;   # not our skill -> no-op passthrough
esac

python3 <<'PY'
import json
ctx = (
    "JALAN A AUTO-DELEGATE — TWO-TIER EXECUTOR. This is big/multi-step work: launch ONE "
    "`gx --team <spec.md>` (or `gx --team --new \"<brief + gate>\"`), do NOT micro-manage "
    "per-step. `gx --team` runs the two-tier executor: a GLM-5.2 LEAD decomposes the spec and "
    "delegates the coding to the deepseek-v4-pro @coder subagent (one opencode task), which "
    "writes AND runs tests to green. Gate baked into the spec: implement + tests-to-green, no "
    "placeholder/TODO/mock, DON'T commit. Then TERIMA-BERES: review the finished diff wholesale "
    "+ run verify + commit (commit stays with you). CHAIN OF COMMAND — Opus (you) = judgment "
    "(brainstorm/plan/debug/review/verify-gate/commit); the executor = codegen + TDD. Iterative "
    "fix rides the same session: `gx \"<delta>\"`. Pools live in the agent config: DEFAULT = "
    "opencode-go (glm-5.2 lead + deepseek), FAILOVER = ollama (glm-5.2 + kimi) — `gx` auto-fails "
    "over; you never hand-swap models. A bounded single-file mechanical edit can use plain `gx "
    "\"<brief>\"` (deepseek solo, no lead). Gotcha: spec + targets INSIDE the repo; run from repo "
    "root. The per-step write-test->gx->review LOOP across a multi-phase plan is the ANTI-PATTERN "
    "(2x tokens) — the spec file IS the spec, deltas carry the rest."
)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": ctx}}))
PY
