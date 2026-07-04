#!/usr/bin/env bash
# model-router code-delegate hook — PreToolUse on Write|Edit.
# Fires on ANY substantive code file: BLOCKS the hand-edit so the change is FORCED through the
# executor. The remedy is MODE-AWARE (session mode marker ~/.config/model-router/mode):
#   anthropic-team (DEFAULT) → delegate to a Sonnet-5 Agent (native Claude Code Agent tool)
#   anthropic-solo           → allow the direct Opus edit (bypass marker is set by the selector)
#   opencode | ollama        → route through `gx` / `gx --team`
# ponytail: a hook can only inject text or block — it CANNOT run the Agent tool or gx. It names
# the right entry point; Claude issues the actual call. gx/opencode + the Agent-tool subagent
# edit files via their OWN process, so DENYing Claude's Edit does NOT block them (clean split).
# BYPASS (failover / tiny reviewed fix): `touch ~/.config/model-router/allow-direct-edit`.
set -euo pipefail

MODE_MARKER="${ROUTER_MODE:-$HOME/.config/model-router/mode}"
MODE="anthropic-team"   # default
if [[ -s "$MODE_MARKER" ]]; then MODE="$(<"$MODE_MARKER")"; MODE="${MODE//[$'\n\r']/}"; fi
BYPASS="${GX_BYPASS_MARKER:-$HOME/.config/model-router/allow-direct-edit}"

INPUT="$(cat)"
FP="$(printf '%s' "$INPUT" | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))
except Exception: print('')" 2>/dev/null || true)"

# Only CODE files. Docs/config/specs/shell stay on Claude (delegation machinery, CLAUDE.md,
# i18n json edited inline is fine — the point is impl/test/refactor code).
case "$FP" in
  *.py|*.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.vue|*.svelte|*.go|*.rs|*.java|*.rb|*.php|*.c|*.cc|*.cpp|*.h|*.hpp|*.cs|*.kt|*.kts|*.swift|*.scala|*.sql) ;;
  *) exit 0 ;;
esac

# anthropic-solo OR bypass marker → allow the direct edit (Opus codes; or operator-sanctioned fix).
if [[ "$MODE" == "anthropic-solo" || -e "$BYPASS" ]]; then exit 0; fi

# else HARD BLOCK with a mode-specific remedy.
MODE="$MODE" BYPASS="$BYPASS" python3 <<'PY'
import json, os
mode = os.environ["MODE"]
bp = os.environ["BYPASS"]

if mode == "ollama":
    how = ("route through the ollama executor: `gx --team <spec.md>` (GLM-5.2 lead → @coder-ff "
           "kimi-k2.7-code) for a feature, or `gx \"<brief>\"` (kimi solo) for a bounded edit")
elif mode == "opencode":
    how = ("route through the opencode executor: `gx --team <spec.md>` (GLM-5.2 lead → @coder "
           "deepseek-v4-pro) for a feature, or `gx \"<brief>\"` (deepseek solo) for a bounded edit")
else:  # anthropic-team (default)
    how = ("delegate to a Sonnet-5 executor via the Agent tool: subagent_type='general-purpose', "
           "model='sonnet', prompt = the whole-task spec + hard gate (implement + write & RUN tests "
           "to green, no placeholder/TODO/mock, DON'T commit). Do NOT hand-type the code yourself")

reason = (
    f"BLOCKED — code change must go through the executor (session mode: {mode}). "
    f"Do NOT hand-edit product source with Edit/Write. Instead: {how}. The executor edits files "
    f"via its OWN process, so this block does NOT stop it. Then TERIMA-BERES: review the finished "
    f"diff + run verify + commit (commit stays with you). FAILOVER / operator-sanctioned tiny fix "
    f"ONLY: `touch {bp}` to bypass, then `rm {bp}` to re-arm."
)
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": reason,
}}))
PY
