#!/usr/bin/env bash
# model-router session-mode hook — SessionStart.
# Injects the current executor MODE and instructs Claude to confirm/choose it via AskUserQuestion
# on turn 1, so the operator picks the executor up front (never waits for a token-exhaustion
# failover). A hook can only inject text — it cannot pop a dialog; Claude runs the AskUserQuestion.
# Marker: ~/.config/model-router/mode ∈ anthropic-team | anthropic-solo | opencode | ollama.
# Default (unset) = anthropic-team (Opus brain + Sonnet-5 executor — cheapest Opus-brain option).
# ponytail: python3 emits the JSON (correct escaping).
set -euo pipefail

MODE_MARKER="${ROUTER_MODE:-$HOME/.config/model-router/mode}"
MODE="anthropic-team"
if [[ -s "$MODE_MARKER" ]]; then MODE="$(<"$MODE_MARKER")"; MODE="${MODE//[$'\n\r']/}"; fi

MODE="$MODE" MARKER="$MODE_MARKER" python3 <<'PY'
import json, os
mode = os.environ["MODE"]
marker = os.environ["MARKER"]
bypass = os.path.join(os.path.dirname(marker), "allow-direct-edit")
ctx = (
    f"MODEL-ROUTER SESSION MODE = `{mode}` (executor for this session). On turn 1, CONFIRM or "
    f"change it with AskUserQuestion, pre-selecting the current/default `anthropic-team`:\n"
    f"  Q1 Brain: Anthropic (Opus) [default]  |  Multi-modal (GLM via opencode/ollama)\n"
    f"  Q2 Executor: if Anthropic → Sonnet 5 [= anthropic-team, DEFAULT] or Opus-solo [anthropic-solo]; "
    f"if Multi-modal → Opencode-go [opencode] or Ollama [ollama].\n"
    f"After the operator answers, WRITE the choice to `{marker}` and apply it:\n"
    f"  • anthropic-team → `rm -f {bypass}` (code-delegate hook then routes code edits to a Sonnet-5 "
    f"Agent: subagent_type=general-purpose, model=sonnet, spec+gate; you review the diff + commit).\n"
    f"  • anthropic-solo → `touch {bypass}` (you code directly; the code-delegate block is bypassed).\n"
    f"  • opencode → `rm -f {bypass}` + `route default`; use `gx --team` (GLM lead → @coder deepseek) / "
    f"`gx` solo.\n"
    f"  • ollama → `rm -f {bypass}`; `gx --team`/`gx` then use the ollama pair (glm-5.2 + kimi-k2.7-code).\n"
    f"Ownership every mode: judgment (brainstorm/plan/debug/review/verify-gate/commit) = Opus (GLM "
    f"`brain` only if the Anthropic subscription is out → `route panic --run`); codegen + TDD = the "
    f"executor; review is never skipped; commit stays with a supervisor (you, or the human in panic)."
)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx}}))
PY
