# model-router

Executor-tier model router for Claude Code. One config, one command (`route`) to switch the
bulk-codegen backend between **opencode (DeepSeek-V4-Pro)** and **ollama (GLM-5.2)** — with
automatic failover. The thinking/review brain stays on your Claude subscription.

## What it does (and what it can't)

Three model surfaces exist; this tool governs exactly one:

| Surface | Runs | Governed here? |
|---|---|---|
| brain | `gaspol-brainstorm` / `plan` / `review` / `debug` + commit gate (Opus, subscription) | ❌ Anthropic-fixed (see limitation) |
| subagents | gaspol-dev review/verify (opus/sonnet/haiku) | ❌ Anthropic-fixed |
| **executor** | ALL other execution (`gaspol-execute` / `tdd` / `parallel` + bulk impl + test authoring) via `gx` / autonomous `opencode run` | ✅ **this plugin** |

### Chain of command (LOCKED 2026-07-03)

Three tiers, not two. Opus stays strategy; the executor is itself split into a lead and a laborer:

- **Opus 4.8 = strategy** — the 4 judgment skills above + the commit/push gate. Writes ONE whole-task spec + hard gate, then reviews the finished diff (terima-beres — no per-step micro-management).
- **GLM-5.2 (ollama) = execution LEAD / right hand** — the autonomous `opencode run -m ollama/glm-5.2:cloud` that OWNS execution: runs the bulk pass, **supervises + fixes deepseek's output**, takes the hard/long-context/critical slices directly (migration/auth/threshold — stronger on coding benches), writes & RUNS tests to green, hands back ONE clean diff. Never commits.
- **deepseek-v4-pro (opencode-go) = bulk labor** — cheap high-volume first-draft codegen + mechanical mass edits (flash for pure rename/i18n).

Critical files (migration/auth/deploy-gate/threshold) are still IMPLEMENTED by the executor; the guardrail is that Opus **reviews them harder**, not that Opus types them. The per-step `write-test → gx → review` loop across a multi-phase plan is the anti-pattern (≈2× tokens) — prefer one autonomous run per task.

### Known limitation — brain is NOT multi-model on a subscription

`claude-code-router` cannot proxy a Claude Pro/Max **subscription**
([ccr #482](https://github.com/musistudio/claude-code-router/issues/482), open since Aug 2025):
turn ccr on and you lose Opus entirely; leave it off and there is no GLM path for the brain.
So the brain + gaspol subagents stay Anthropic. Only the **executor** is routed. This is free
(flat subscription) and covers the bulk-token surface (codegen).

## Invariant

- `GLM-5.2 → ollama` ONLY · `deepseek-v4-pro/flash → opencode-go` ONLY. Never cross.
- Reason: **separate quota pools** — brain-GLM (ollama) and executor-deepseek (opencode-go)
  drain independent pools, so one running out never starves the other.

## Install

```bash
./install.sh           # symlinks config + route/router-doctor/gx + delegate hooks into $HOME
route default          # set the default executor
router-doctor          # check which backends you have (bring your own accounts)
```

### Two delegate hooks (LOCKED 2026-07-03)

Delegation fires on **any substantive code change**, not just when a gaspol skill runs:

- `hooks/delegate.sh` — PreToolUse on **`Skill`** (`gaspol-execute`/`gaspol-parallel`).
- `hooks/code-delegate.sh` — PreToolUse on **`Write|Edit`**, gated to code extensions
  (`.py/.ts/.vue/.js/.go/.rs/.sql/…`, skips docs/config/i18n/spec). Catches a plain
  request the moment the brain reaches for an `Edit` on product source — no skill needed.

Both inject the same chain-of-command directive naming the active executor. A hook is a
**nudge** (injects text / can block) — it CANNOT run opencode or swap the brain's `Edit`
for `gx`; the actual `opencode run` is a Bash call the brain issues. Nudge, not block, so
failover / tiny-reviewed-fix / docs edits still pass. Register `Write|Edit` in
`~/.claude/settings.json` PreToolUse (install.sh symlinks the hook; the settings entry is
one-time). Hooks load at SESSION START.

Requires: `opencode` (with auth) for DeepSeek, `ollama` (signed in) for GLM-5.2 cloud, python3.

## Usage

```bash
route                    # show active executor
route default            # deepseek-v4-pro  (cheapest workhorse — DEFAULT)
route glm-heavy          # glm-5.2:cloud    (hard/long-context/quality-critical)
route mechanical         # deepseek-v4-flash (rename/i18n/mass-edit)
route failover-opencode  # glm-5.2:cloud    (opencode pool dead)
route offline            # local qwen3-coder
```

`gx` resolves its model as `-m flag > $GX_MODEL > router state > default`, and **auto-failovers**
a dead opencode-go pool to `ollama/glm-5.2:cloud` once (separate pool). The delegate hook injects
the active executor model into gaspol-execute / gaspol-parallel automatically.

### Weekly-max escape hatch

When your Anthropic **weekly** limit hits, the brain (this session) stops — it cannot auto-failover
(you can't hot-swap a running session's own auth). Switch manually to a GLM orchestrator:

```bash
route panic              # prints the command
route panic --run "..."  # launches: opencode run -m ollama/glm-5.2:cloud (GLM as brain)
```

## Model choice (why DeepSeek is the default executor)

Independent benchmarks: GLM-5.2 is stronger at coding (near Opus 4.8), but DeepSeek-V4-Pro is
~4× cheaper per token. The executor only *types* the spec the brain already reasoned out, so
DeepSeek is the cost-optimal default; GLM-5.2 escalates for hard/ambiguous/long-context work
where its one-shot success beats DeepSeek's retries.

## Tests

```bash
for t in tests/test_*.sh; do bash "$t"; done   # bash asserts, no framework
```
