#!/usr/bin/env bash
# model-router code-delegate hook — PreToolUse on Write|Edit.
# Fires on ANY substantive code file (not just when a gaspol skill was invoked):
# nudges Claude to route the change through the executor (one autonomous opencode
# run — GLM-5.2 lead + deepseek), instead of hand-editing. Skips docs/config/specs.
# ponytail: a hook can only inject text or block — it CANNOT run opencode or swap
# Claude's Edit for gx. This is a NUDGE; the actual `gx`/`opencode run` is still a
# Bash call Claude issues. Nudge (not block) so failover/critical-review edits pass.
set -euo pipefail

STATE="${ROUTER_STATE:-$HOME/.config/model-router/state}"
if [[ -s "$STATE" ]]; then MODEL="$(<"$STATE")"; MODEL="${MODEL//[$'\n\r']/}"; else MODEL="opencode-go/deepseek-v4-pro"; fi

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

MODEL="$MODEL" python3 <<'PY'
import json, os
m = os.environ["MODEL"]
ctx = (
    f"CODE CHANGE — DELEGATE TO EXECUTOR (active: {m}). Standing policy (LOCKED 2026-07-03): "
    f"EVERY substantive code change (impl/test/refactor of product source) goes to the executor, "
    f"NOT gated on a gaspol-execute/parallel skill being invoked. Instead of hand-editing this "
    f"file, write ONE whole-task spec + hard gate (implement + write & RUN tests to green, no "
    f"placeholder, DON'T commit) and launch ONE autonomous run — `opencode run -m {m} \"<spec>\"` "
    f"(full-tools, iterates to green itself; GLM-5.2@ollama for hard/long-context/critical slices, "
    f"deepseek-v4-pro@opencode-go for bulk) — then TERIMA-BERES: review the finished diff wholesale "
    f"+ run tests once + commit. `gx <spec>.md` (edit-only) only for a bounded single-file "
    f"mechanical edit. STAY on Claude (proceed with this Edit, ignore this nudge) ONLY for: docs/"
    f"config/i18n/spec files, a tiny reviewed fix you're applying, or when the executor is down "
    f"(failover). INVARIANT: GLM-5.2 -> ollama ONLY, deepseek -> opencode-go ONLY. Spec + targets "
    f"INSIDE the repo; run from repo root."
)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": ctx}}))
PY
