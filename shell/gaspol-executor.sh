# model-router → gaspol-dev bridge (the PRODUCER of $GASPOL_EXECUTOR).
#
# gaspol-dev's "Execution Handoff → Option 4" reads $GASPOL_EXECUTOR (a generic contract, like
# $EDITOR). gaspol-dev knows nothing about model-router; this file is Ali's private wiring that
# fills that var. On a machine without model-router the var is simply unset and Option 4 hides.
#
# Conditional on session mode: expose the external executor ONLY in `opencode` mode. In
# anthropic-team/solo the executor is a Sonnet Agent (native Agent tool via the code-delegate
# hook), NOT a CLI — so Option 4 must stay hidden there.
#
# Sourced from ~/.zshrc. Claude Code's Bash tool re-initialises from the profile on every call,
# so this re-evaluates per invocation and tracks `route`/mode-picker changes with no stale value.
if [ "$(cat "${HOME}/.config/model-router/mode" 2>/dev/null)" = opencode ]; then
  export GASPOL_EXECUTOR='gx --team {plan}'
else
  unset GASPOL_EXECUTOR 2>/dev/null || true
fi
