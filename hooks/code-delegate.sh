#!/usr/bin/env bash
# model-router code-delegate hook — PreToolUse on Write|Edit.
# Fires on ANY substantive code file (not just when a gaspol skill was invoked):
# BLOCKS the hand-edit so the change is FORCED through the executor (one autonomous
# opencode run — GLM-5.2 lead + deepseek). Skips docs/config/specs.
# ponytail: a hook can only inject text or block — it CANNOT run opencode or swap
# Claude's Edit for gx. gx/opencode edit files via their OWN process, NOT Claude's
# Edit tool, so DENYing Claude's Edit does NOT block gx (clean separation).
# BYPASS (failover / tiny reviewed fix): `touch ~/.config/model-router/allow-direct-edit`
# lets direct Edits through; `rm` it to re-arm the block. LOCKED 2026-07-03.
set -euo pipefail

STATE="${ROUTER_STATE:-$HOME/.config/model-router/state}"
if [[ -s "$STATE" ]]; then MODEL="$(<"$STATE")"; MODEL="${MODEL//[$'\n\r']/}"; else MODEL="opencode-go/deepseek-v4-pro"; fi

BYPASS="${GX_BYPASS_MARKER:-$HOME/.config/model-router/allow-direct-edit}"

INPUT="$(cat)"
FP="$(printf '%s' "$INPUT" | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))
except Exception: print('')" 2>/dev/null || true)"

# Only CODE files. Docs/config/specs/shell stay on Claude (delegation machinery,
# CLAUDE.md, i18n json edited inline is fine — the point is impl/test/refactor code).
case "$FP" in
  *.py|*.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.vue|*.svelte|*.go|*.rs|*.java|*.rb|*.php|*.c|*.cc|*.cpp|*.h|*.hpp|*.cs|*.kt|*.kts|*.swift|*.scala|*.sql) ;;
  *) exit 0 ;;
esac

# Bypass marker present → allow the direct edit (failover / operator-sanctioned tiny fix).
if [[ -e "$BYPASS" ]]; then exit 0; fi

# No bypass → HARD BLOCK. Deny the Edit/Write and tell Claude to route through gx.
MODEL="$MODEL" BYPASS="$BYPASS" python3 <<'PY'
import json, os
m = os.environ["MODEL"]
bp = os.environ["BYPASS"]
reason = (
    f"BLOCKED — code change must go through the executor (active: {m}), LOCKED 2026-07-03. "
    f"Do NOT hand-edit product source with Edit/Write. Instead: write ONE whole-task spec + hard "
    f"gate (implement + write & RUN tests to green, no placeholder, DON'T commit) and launch ONE "
    f"autonomous run — `gx <spec>.md \"<gate>\"` if a plan/spec file exists, else `gx --new \"<brief "
    f"+ gate>\"` (inline). Iterative fix on the same task → `gx \"<delta>\"` (continues the session). "
    f"gx/opencode edit files via their own process, so this block does NOT stop them. Then "
    f"TERIMA-BERES: review the finished diff + run tests once + commit. INVARIANT: GLM-5.2 -> ollama "
    f"ONLY, deepseek -> opencode-go ONLY. FAILOVER / operator-sanctioned tiny fix ONLY: run "
    f"`touch {bp}` to bypass this block, then `rm {bp}` to re-arm."
)
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": reason,
}}))
PY
