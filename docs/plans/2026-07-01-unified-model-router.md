# Model Router (executor-tier) — Design

> Status: design approved (gaspol-brainstorm 2026-07-01), direction **A** (subscription + executor-only).
> Next: gaspol-plan appends `## Implementation Plan`. Target: personal-first, public-ready Claude Code plugin.

## Problem

Model routing across 3 backends is scattered (prose + hardcoded gx + separate configs):
- **Opus 4.8 (brain)** = Claude Code CLI *subscription* (OAuth)
- **deepseek-v4-pro/flash (cheap executor)** = opencode-go tier
- **GLM-5.2 (strong executor)** = ollama cloud

No SSOT, no one-command switch, no auto-failover. Research (2026-07-01, z.ai blog + Semgrep) confirms
GLM-5.2 beats deepseek-v4-pro on most coding benches (SWE-bench Pro 62.1 vs 55.4, Terminal-Bench 81.0 vs 64.0,
FrontierSWE 74.4 vs 29.0), 1M context, MIT license — so it is a genuine executor upgrade, not just a fallback.

## KNOWN LIMITATION (the wall — why brain/review are NOT multi-model)

**ccr (claude-code-router) CANNOT proxy a Claude Pro/Max subscription.** Evidence: ccr issue
[#482](https://github.com/musistudio/claude-code-router/issues/482) — open since Aug 2025, still unimplemented
Mar 2026; subscription passthrough "would need a separate provider," and CCS/docker-claude-code only *switch*
providers by restarting. Local proof: our ccr config has `APIKEY: false` and zero Anthropic provider.

Consequence — **mutually exclusive**:
- `ccr ON` → no path to Anthropic subscription → everything routes to ollama-glm → **Opus is lost**.
- `ccr OFF` → everything native Anthropic subscription → **no glm for brain/subagents**.

There is NO "Opus-subscription brain + glm subagents" in one session. This is why repeated attempts to make
gaspol-dev's thinking/review layers multi-model failed — not a bug, an unfixed ccr limitation.

**Decision (direction A):** keep the Opus subscription; make ONLY the executor multi-model. Brain + subagents
stay Anthropic by design. This is free (flat subscription) and covers the bulk-token surface (codegen).

## The three surfaces (only ONE is router-governed)

| # | Surface | Runs | Backend | Router-governed? |
|---|---|---|---|---|
| A | **session brain** | plan/brainstorm/design (Opus) | Anthropic subscription (native) | ❌ fixed — ccr can't proxy sub (#482) |
| B | **session subagents** | gaspol-dev review/verify/simplify (opus/sonnet/haiku pins) | Anthropic subscription (native) | ❌ fixed — same wall; agent files untouched |
| C | **executor** | bulk codegen: implement + simple-plan delegation | opencode (deepseek) / ollama (glm) | ✅ **YES — this plugin** |

Surface C is auth-independent: `gx` shells out to `opencode run` via Bash, using opencode's own auth
(`~/.local/share/opencode/auth.json`) — never touches Claude Code's auth. So it works identically in the
VSCode extension, CLI, subscription, or API mode. **This is the whole multi-model surface.**

## Hard constraints (locked)

1. **Provider-pinning invariant (ALWAYS, incl. panic/failover):** `GLM-5.2 → ollama ONLY`; `deepseek-v4-pro/flash → opencode-go ONLY`. Never cross (no `opencode-go/glm`, no `ollama/deepseek`). Reason: **separate quota pools** — if brain-GLM ran on opencode-go it would fight the deepseek executor for the same pool; keeping GLM on ollama + deepseek on opencode-go means brain and executor drain independent pools and both survive longer.
2. **deepseek → opencode-go ONLY** (`-pro` workhorse, `-flash` mechanical). Never API, never ollama. Cheapest.
3. **Opus 4.8 → Claude Code CLI subscription, NOT API.** Brain is the running session; never routed. ccr out of daily scope.
4. **Opus = think/decide/review; GLM/deepseek = type.** Never delegate thinking; never burn Opus on bulk codegen.
5. **Brain + subagents = Anthropic-fixed** (see KNOWN LIMITATION). Router governs the executor only.
6. **Panic brain = `opencode run -m ollama/glm-5.2:cloud`** (GLM on ollama pool) — respects invariant #1; keeps executor's opencode-go pool intact.

## Tiering (task-class → tier)

| task-class | tier | where it runs |
|---|---|---|
| plan.complex / review / test-authoring / critical | brain | **session (Opus subscription)** — not routed, not delegated |
| plan.simple | heavy | executor: `gx -m ollama/glm-5.2:cloud` (delegated, same path as implement) |
| implement (default) | workhorse | executor: `opencode-go/deepseek-v4-pro` |
| implement.heavy / long-context / quality-critical | heavy | executor: `ollama/glm-5.2:cloud` |
| implement.mechanical (rename/i18n/mass-edit) | mechanical | executor: `opencode-go/deepseek-v4-flash` |
| offline / private | offline | executor: `ollama/qwen3-coder:30b-a3b-q8_0` (local) |

**critical class** (never delegated, stays brain): auth, migration, money/payments, threshold/verdict logic, security.
Complexity gate = orchestrator (Opus) judgment + hook directive; NOT a runtime classifier.

## Profiles (`route <profile>` — governs the EXECUTOR only)

| Profile | executor default (gx) | When |
|---|---|---|
| `default` | opencode-go/deepseek-v4-pro | normal (cheapest workhorse) |
| `glm-heavy` | ollama/glm-5.2:cloud | heavy batch / quality-first |
| `mechanical` | opencode-go/deepseek-v4-flash | mass mechanical edits |
| `failover-opencode` | ollama/glm-5.2:cloud | opencode token/quota dead (AUTO switch) |
| `offline` | ollama/qwen3-coder:30b-a3b-q8_0 | no network / private |

`route` writes the active executor model to a state file that `gx` reads. No ccr, no daemon, no session relaunch.

## Failover

| Side | Auto? | Mechanism |
|---|---|---|
| Executor (opencode → ollama) | **AUTO** | gx wrapper: on opencode quota/auth error (non-zero exit / known stderr), auto-retry once with `ollama/glm-5.2:cloud`; log the switch |
| Brain (Opus subscription dead) | **out of scope** | can't hot-swap subscription; emergency = manually run `ccr code` in a terminal (separate all-glm session). NOT part of this plugin. |

## Architecture (plugin, personal-first / public-ready)

```
~/Drive-D/Projects/model-router/            # git repo, plugin home
├── .claude-plugin/plugin.json              # manifest (name, version, hook registration)
├── router.config.jsonc                     # SSOT: tiers + task-class routing + executor profiles (Ali profile filled)
├── bin/
│   ├── route                               # profile switcher: write active executor model to state file; print state
│   └── router-doctor                       # detect backends present (opencode auth? ollama signin? which models?), warn missing
├── hooks/
│   └── delegate.sh                         # PreToolUse on Skill(gaspol-execute|parallel): inject delegate directive,
│                                           #   read executor model from router.config.jsonc state (generalize existing hook)
└── README.md
```

### SSOT config shape (router.config.jsonc)

```jsonc
{
  "tiers": {
    "brain":      { "surface": "claude-subscription", "route": false },   // Opus — session, never routed
    "heavy":      { "surface": "opencode", "model": "ollama/glm-5.2:cloud" },
    "workhorse":  { "surface": "opencode", "model": "opencode-go/deepseek-v4-pro" },
    "mechanical": { "surface": "opencode", "model": "opencode-go/deepseek-v4-flash" },
    "offline":    { "surface": "opencode", "model": "ollama/qwen3-coder:30b-a3b-q8_0" }
  },
  "route": {
    "plan.complex": "brain", "review": "brain", "test-authoring": "brain", "critical": "brain",
    "plan.simple": "heavy",
    "implement": "workhorse", "implement.heavy": "heavy", "implement.mechanical": "mechanical"
  },
  "activeProfile": "default",
  "profiles": {
    "default":           "opencode-go/deepseek-v4-pro",
    "glm-heavy":         "ollama/glm-5.2:cloud",
    "mechanical":        "opencode-go/deepseek-v4-flash",
    "failover-opencode": "ollama/glm-5.2:cloud",
    "offline":           "ollama/qwen3-coder:30b-a3b-q8_0"
  },
  "autoFailover": { "executor": true }
}
```

### gx model resolution (SSOT, no hardcode)

`-m` flag  >  `$GX_MODEL`  >  active profile in state file  >  fallback `opencode-go/deepseek-v4-pro`.
Executor auto-failover: wrap the `opencode run` call; on quota/auth failure retry once with `ollama/glm-5.2:cloud`, log it.

## Data Integration Map

| Component | Source | Exists? | Action |
|---|---|---|---|
| router.config.jsonc (SSOT) | new | ❌ | create; fill Ali profile |
| bin/route | new | ❌ | create — write active executor model to state file; print state |
| bin/router-doctor | new | ❌ | create — backend detection (opencode/ollama/models), thin |
| gx | ~/.local/bin/gx | ✅ | modify: read config/state not hardcode; add executor auto-failover |
| delegate hook | ~/.claude/hooks/gaspol-opencode-delegate.sh | ✅ | generalize to read router.config.jsonc; move into plugin (or symlink) |
| opencode.jsonc models | ~/.config/opencode/opencode.jsonc | ✅ | DONE this session (glm/kimi/minimax:cloud added) |
| gaspol-dev subagents | plugin agent frontmatter | ✅ | UNTOUCHED — Anthropic-fixed by design (#482) |
| ccr | ~/.claude-code-router/ | ✅ | OUT of scope — emergency all-glm CLI session only, not driven by this plugin |
| Opus complexity-gate | policy/directive | ⚠️ | encode in config + hook directive; enforced by orchestrator |

## Skipped (YAGNI / blocked — with reason)

- **Brain + subagent multi-model** — BLOCKED by ccr #482 (can't proxy subscription). Not achievable without dropping subscription (option B) or a LiteLLM OAuth-passthrough proxy (option D, ToS-risky). Revisit if #482 ships.
- Brain-side auto-failover (can't hot-swap subscription).
- ccr daemon management in `route` (dropped — executor router needs no ccr).
- UI/dashboard; auto task-class classifier; marketplace publish + full public docs (public-release milestone).
- kimi-k2.7-code / minimax-m3 active routing (models wired; add as alt executor tiers when needed).

## Verification (per non-trivial logic)

- `route <profile>` self-check: apply profile → assert state file matches → `gx` (dry) reports expected model; `route default` restores.
- gx auto-failover: force opencode failure (bad model id / unset auth) → assert retry hits `ollama/glm-5.2:cloud` and logs the switch.
- router-doctor: run on Ali's machine → opencode + ollama backends green, all 4 cloud models listed.

---

# Implementation Plan

> **For Claude:** REQUIRED SKILL: Use gaspol-execute to implement this plan.
> **CRITICAL:** Real integrations only. NEVER substitute placeholders without explicit approval. If a data
> source doesn't exist, STOP and ask. This plan is **not delegated** to gx per class: the scripts here are
> plumbing (config/state/env), low-risk — bulk edits MAY go via `gx`, but the auto-failover retry logic and
> the hook JSON contract are **verdict/threshold-ish plumbing → author on Claude**, review every diff.

## Goal

Ship a config-driven **executor-tier** model router as a personal-first, public-ready Claude Code plugin.
`route <profile>` flips the bulk-codegen backend (deepseek ⇄ glm) via a state file that `gx` reads; gx gains
auto-failover (opencode dead → ollama-glm). Brain + subagents stay Anthropic subscription by design (ccr #482 wall).

## Architecture Context

- **gx** (`~/.local/bin/gx`, on PATH) already delegates implement → `opencode run`. Modify in place: model
  resolution `-m > $GX_MODEL > state-file > default`, plus one-retry auto-failover.
- **delegate hook** (`~/.claude/hooks/gaspol-opencode-delegate.sh`) fires PreToolUse on Skill(gaspol-execute|parallel),
  injects the JALAN-A directive with a hardcoded model. Generalize: read active model from state file.
- **opencode.jsonc** already has `ollama/{glm-5.2,kimi-k2.7-code,minimax-m3}:cloud` + local qwen (done this session).
- **ccr** = out of scope (emergency all-glm CLI only).

## Tech Stack

Bash (scripts), JSONC config, `jq` OR `python3` for parse (both present; prefer `python3` — no jq dependency = public-portable).
State: `~/.config/model-router/state` (one line = active executor model). Config: `~/.config/model-router/router.config.jsonc`
(symlinked from plugin by `install.sh`). Tests: plain bash assert scripts under `tests/` (no framework — ponytail). Lint: `shellcheck`.

## Data Integration Map

| Feature | Data Source | Access | Exists? | Action |
|---|---|---|---|---|
| active executor model | `~/.config/model-router/state` | `cat` (gx, hook read) | No | Create — `route` writes it |
| profile → model map | `router.config.jsonc` `.profiles` | `python3 -c json.load` | No | Create in plugin |
| executor delegation | `opencode run --agent executor -m <model>` | gx shell-out | Yes | Reuse (gx line 37) |
| cloud model availability | `ollama list` / `opencode models` | doctor greps | Yes | Reuse (read-only) |
| opencode auth | `~/.local/share/opencode/auth.json` | doctor stat | Yes | Reuse (existence check) |
| hook directive | delegate hook stdout JSON | `hookSpecificOutput.additionalContext` | Yes | Modify — inject state model |

## Phases

### Phase A: Scaffold + SSOT config

**Files:** Create `.claude-plugin/plugin.json`, `router.config.jsonc`, `tests/assert.sh` (tiny helper), `install.sh`.

**Steps:**
1. Write failing test `tests/test_config.sh`: assert `router.config.jsonc` parses via python3 AND has keys `.profiles.default`, `.tiers.workhorse.model`. Expected error: `test_config: FAIL router.config.jsonc not found`.
2. Run `bash tests/test_config.sh`, confirm it fails for that reason.
3. Create `router.config.jsonc` (exact shape from design §SSOT config), `plugin.json` (name `model-router`, version `0.1.0`), `tests/assert.sh` (`assert_eq`/`fail` helpers).
4. Run test, confirm pass.
5. Commit: "feat: scaffold model-router plugin + SSOT config".

**Verification:**
- [ ] `shellcheck tests/*.sh install.sh` clean
- [ ] `python3 -c "import json,re; json.loads(re.sub(r'//.*','',open('router.config.jsonc').read()))"` parses
- [ ] config has all 5 profiles + 5 tiers; no placeholder/TODO
- [ ] `bash tests/test_config.sh` passes

### Phase B: `route` CLI

**Files:** Create `bin/route`, `tests/test_route.sh`.

**Steps:**
1. Write failing test: `bin/route glm-heavy` then assert `~/.config/model-router/state` == `ollama/glm-5.2:cloud`; `bin/route default` → `opencode-go/deepseek-v4-pro`; unknown profile → non-zero exit. Expected error: `test_route: FAIL bin/route not found`.
2. Run test, confirm fail.
3. Implement `bin/route`: read profile arg → look up `.profiles[arg]` in config (python3) → write model to state file (mkdir -p parent) → print `route → <profile> | executor=<model>`. Unknown profile → error + list valid, exit 2. No arg → print current state.
4. Run test, confirm pass.
5. Commit: "feat: route profile switcher".

**Verification:**
- [ ] `shellcheck bin/route` clean
- [ ] `route glm-heavy` writes correct model; `route default` restores; bad profile exits 2
- [ ] no placeholder/TODO
- [ ] `bash tests/test_route.sh` passes

### Phase C: gx SSOT model resolution

**Files:** Modify `~/.local/bin/gx`; Create `tests/test_gx_resolve.sh`.

**Steps:**
1. Write failing test: set state=`ollama/glm-5.2:cloud`, run `gx --print-model` (new dry flag) → expect that model; `GX_MODEL=x gx --print-model` → `x`; `gx -m y --print-model` → `y`; no state + no env → `opencode-go/deepseek-v4-pro`. Expected error: `unknown flag --print-model`.
2. Run test, confirm fail.
3. Modify gx: resolution `-m > $GX_MODEL > $(cat state 2>/dev/null) > default`. Add `--print-model` (resolve + echo + exit 0, no opencode call).
4. Run test, confirm pass.
5. Commit: "feat: gx reads router state (SSOT model resolution)".

**Verification:**
- [ ] `shellcheck ~/.local/bin/gx` clean (no new warnings)
- [ ] all 4 resolution precedence cases correct
- [ ] existing gx behavior (spec file → opencode run) unchanged when state absent
- [ ] `bash tests/test_gx_resolve.sh` passes

### Phase D: gx executor auto-failover  ⚠️ author on Claude (retry logic)

**Files:** Modify `~/.local/bin/gx`; Create `tests/test_gx_failover.sh`.

**Steps:**
1. Write failing test: stub `opencode` on PATH that exits 1 with `error: quota exceeded` (fixture); run gx with a dummy spec → assert stderr shows `gx: opencode failed → failover ollama/glm-5.2:cloud` AND the retry invokes stub with `-m ollama/glm-5.2:cloud`. Expected error: no failover line (single attempt).
2. Run test, confirm fail.
3. Implement: capture `opencode run` exit; on non-zero AND active model is an `opencode-go/*` model (not already ollama), retry ONCE with `ollama/glm-5.2:cloud`; log the switch to stderr. Guard: don't loop, don't failover an already-ollama model. `ponytail:` comment naming the ceiling (single retry; add backoff if flaky).
4. Run test, confirm pass.
5. Commit: "feat: gx one-shot executor auto-failover to ollama-glm".

**Verification:**
- [ ] `shellcheck ~/.local/bin/gx` clean
- [ ] failover fires only on opencode-tier failure; ollama model does NOT re-failover (no loop)
- [ ] success path (exit 0) never retries
- [ ] `bash tests/test_gx_failover.sh` passes

### Phase E: delegate hook generalization  ⚠️ author on Claude (JSON contract)

**Files:** Create `hooks/delegate.sh` (canonical); plan to replace `~/.claude/hooks/gaspol-opencode-delegate.sh` via install symlink; Create `tests/test_hook.sh`.

**Steps:**
1. Write failing test: run `hooks/delegate.sh` with a fake PreToolUse Skill(gaspol-execute) stdin JSON → assert stdout is valid JSON AND `hookSpecificOutput.additionalContext` contains the CURRENT state model (set state=glm → directive names glm). Expected error: `hooks/delegate.sh not found`.
2. Run test, confirm fail.
3. Port existing hook into `hooks/delegate.sh`; replace hardcoded model with `$(cat state || default)`; keep exact JALAN-A directive text otherwise. Validate stdout parses as JSON (python3).
4. Run test, confirm pass.
5. Commit: "feat: delegate hook reads active executor model from state".

**Verification:**
- [ ] `shellcheck hooks/delegate.sh` clean
- [ ] stdout is valid JSON; directive names the state model; fires only for gaspol-execute|parallel
- [ ] non-matching Skill → no-op (empty/passthrough), does not break the tool call
- [ ] `bash tests/test_hook.sh` passes

### Phase F: router-doctor

**Files:** Create `bin/router-doctor`, `tests/test_doctor.sh`.

**Steps:**
1. Write failing test: run `bin/router-doctor --json` → assert JSON with keys `opencode_auth`, `ollama_signin`, `models` (list). Expected error: `bin/router-doctor not found`.
2. Run test, confirm fail.
3. Implement: check `~/.local/share/opencode/auth.json` exists; `ollama list` for `:cloud` models; `opencode models` grep; print human checklist (default) or `--json`. Warn per missing backend with the fix command.
4. Run test, confirm pass.
5. Commit: "feat: router-doctor backend detection".

**Verification:**
- [ ] `shellcheck bin/router-doctor` clean
- [ ] on Ali's machine: opencode_auth ✅, ollama_signin ✅, models lists glm-5.2/deepseek/etc
- [ ] missing-backend path prints the exact fix command; no placeholder
- [ ] `bash tests/test_doctor.sh` passes

### Phase G: `route panic` + install + README + wire live

**Files:** Modify `bin/route` (add `panic`); Finalize `install.sh`; Create `README.md`; Create `tests/test_panic.sh`; run install.

**Steps:**
1. Write failing test `tests/test_panic.sh`: `bin/route panic` (no `--run`) → stdout contains `opencode run -m ollama/glm-5.2:cloud` AND does NOT contain `opencode-go/glm` (invariant #1) AND exit 0 AND does NOT exec opencode (print-only). Also `tests/test_install.sh`: dry-run install into temp HOME → assert symlinks for config + `route`/`router-doctor` + hook. Expected error: `route: unknown command panic`.
2. Run tests, confirm fail.
3. Implement `route panic`: **print** the emergency-brain command (`opencode run -m ollama/glm-5.2:cloud "<your task>"` — GLM via **ollama**, NOT opencode-go; see invariant) + one-line why (Anthropic weekly-max → GLM orchestrator on ollama pool, kept separate from the opencode-go executor pool so both survive); `route panic --run` execs it. Print-only default (safe/reversible). `ponytail:` comment — print-first, `--run` opt-in. Then `install.sh`: symlink `router.config.jsonc`→`~/.config/model-router/`, `bin/*`→`~/.local/bin/`, `hooks/delegate.sh`→`~/.claude/hooks/` (back up existing gaspol hook first, idempotent).
4. README: what/why · **KNOWN LIMITATION #482** (brain not multi-model on subscription) · profiles table · `route panic` weekly-max escape · usage. Run tests, confirm pass. Then real `install.sh`; `route default`; `router-doctor`.
5. Commit: "feat: route panic escape-hatch + install + README; wire live".

**Verification:**
- [ ] `shellcheck bin/route install.sh` clean
- [ ] `route panic` prints the opencode-glm-brain command, exit 0, no exec; `--run` execs (manual-verify only, not in CI)
- [ ] real install: `route glm-heavy && gx --print-model` → glm; `route default` restores; `router-doctor` all green
- [ ] existing gaspol hook backed up (not clobbered); README documents #482 wall + `route panic`
- [ ] `bash tests/test_panic.sh` + `tests/test_install.sh` pass

## Red-flag self-check

- Data Integration Map ✅ · per-phase Verification ✅ · CLAUDE.md/design referenced ✅ · concrete data sources (state file, config keys, exact paths) ✅ · TDD step-1 gate each phase ✅ · phases ≤ ~10 min ✅ · no placeholder language ✅.

## Execution handoff

- Phases are **sequential** (C→D same file; E/F depend on A config) — NOT good parallel candidates except F (doctor) which is independent of C/D/E.
- Critical-ish (author on Claude, no gx): **Phase D** (failover retry) + **Phase E** (hook JSON contract). Phases A/B/F/G plumbing MAY use gx.
