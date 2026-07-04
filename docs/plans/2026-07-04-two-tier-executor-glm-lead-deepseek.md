# Two-tier executor — GLM-5.2 lead → deepseek-v4-pro subagent (opencode)

> **For Claude:** Executor for THIS plan = Opus (me), directly. Every file here is
> config (`.jsonc`), bash (`gx`/`route`/hooks, extensionless), or markdown — none are
> product `.py/.ts/.vue`, so the `code-delegate.sh` hook does not fire and there is nothing
> to hand to the two-tier executor. You do **not** delegate the delegation-wiring to the
> thing being wired (and mid-change the tooling is half-broken anyway). No placeholders:
> every edit is a real file on disk; every phase ends with a runnable smoke that fails first.

## Goal

Make GLM-5.2 a real **execution lead** that assigns coding to a deepseek-v4-pro **subagent**
inside one opencode task — not the current fiction where the delegate hook forces
`route glm-heavy` + `opencode run -m glm`, i.e. **one model (GLM) does 100% and deepseek
never runs** (the reported bug). Smoke-tested live (2026-07-04): with the lead at
`edit:deny`, GLM called the `task` tool → `subagent=coder` → **deepseek-v4-pro wrote the
file** ($0.02/task). This plan productionizes that, in **two modes**:

- **Two-tier** (big work: `gaspol-execute` / `gaspol-parallel`) → `gx --team` → `--agent
  executor` (GLM lead delegates to deepseek `@coder`).
- **Solo** (plain/small delegation) → `gx` → `--agent coder` (deepseek direct, no lead).

**Failover pool (opencode-go token exhausted → ollama):** a SECOND agent pair
`executor-ff` (`ollama/glm-5.2:cloud` lead) + `coder-ff` (`ollama/kimi-k2.7-code:cloud`
executor). opencode pins each agent's model statically and `-m` overrides only the LEAD
(a subagent keeps its config model), so failover cannot be a bare `-m` swap — it needs the
second pair. On an `opencode-go/*` run failure, `gx` retries once on the `-ff` pair
(ollama = the separate failover quota pool, not an always-on route).

**Brain failover (Opus/Anthropic subscription exhausted):** the brain (Opus) is NOT proxyable
(ccr #482) — when the Anthropic quota hits, the Claude Code session dies and Opus cannot even
run the escape itself. Recovery is MANUAL, in the terminal: `route panic --run "<task>"`. Today
that launches `opencode run -m ollama/glm-5.2:cloud` = a lone GLM doing everything (no
delegation) — AND the two-tier `executor` agent is a narrow execution-lead (`edit:deny`,
"delegate coding"), so it has NO owner for the judgment skills (brainstorm/plan/review/debug).
So panic gets a dedicated **`brain`** agent = GLM that OWNS the judgment inline (design + plan +
review reasoning in its prompt) AND delegates bulk coding to `@coder` (deepseek). Decision B
(operator): GLM takes over the full brain when Opus is out — judgment quality degrades to GLM,
but everything keeps moving. **The commit gate stays human:** the panic brain is `bash:deny`
(cannot commit); the operator running `route panic` reviews + commits, so a human stays in the
commit loop even in panic. `brain` runs on `opencode-go/glm-5.2` (default pool, proven
tool-calling) → `brain-ff` (`ollama/glm-5.2:cloud` → `@coder-ff` kimi) only on the rare
opencode-go-also-down double failure.

Plus: fix the **stale symlinks** (the repo moved to `claude-plugin/model-router`; `gx`/`route`/
hooks currently dangle → tooling is DOWN), **drop the GLM→ollama cross-pool invariant** (both
models now `opencode-go`, one pool; the Opus/Anthropic brain stays separate), and **stream
executor events to chat** (opencode block-buffers piped stdout → silent runs today).

## Ownership matrix — WHO does every role, per mode (defined up front)

Two tiers of work. **JUDGMENT** (brainstorm, plan, debug/root-cause, review, verify-gate,
commit) = the brain (always Opus while its subscription is alive). **EXECUTION** (codegen, TDD
write+run tests, mechanical edits, iterate-to-green) = the executor, which is a DIFFERENT model
per mode. Nothing is unowned.

**Four modes** (chosen at session start, Phase 6). `anthropic-team` is the DEFAULT — cheapest
Opus-brain option (bulk codegen on Sonnet stretches the subscription):

| Role | `anthropic-team` (DEFAULT) | `anthropic-solo` | `opencode` / `ollama` | Panic (Anthropic out) |
|---|---|---|---|---|
| Brainstorm / Plan | Opus | Opus | Opus | GLM `brain` (degraded) |
| Codegen / impl | **Sonnet 5** (Agent tool) | Opus | executor (GLM → `@coder` deepseek/kimi) | executor via `@coder` |
| TDD — write+run tests | Sonnet 5 (Agent, has Bash) | Opus | `@coder` (bash:allow) | `@coder` |
| Debug / root-cause | Opus (Sonnet applies fix) | Opus | Opus (executor applies fix) | GLM `brain` |
| Verify — typecheck/lint/build/placeholder | Sonnet→green **then Opus gate** | Opus | executor→green **then Opus gate** | executor→green **then GLM+HUMAN** |
| Review — final diff | **Opus** (`gaspol-review`) | Opus | **Opus** | GLM self **+ HUMAN** |
| Commit / push | Opus | Opus | Opus | **HUMAN** |

Executor identity per mode: `anthropic-team` → **Sonnet 5** via the native Claude Code **Agent
tool** (`subagent_type: general-purpose, model: sonnet`) — NOT opencode, NOT `gx`, all on the
Anthropic subscription. `anthropic-solo` → Opus itself. `opencode` → `gx`/`gx --team` (GLM lead
→ deepseek). `ollama` → same via the `-ff` pair (GLM → kimi).

Hard rules, true in every mode:
- **Verify is two-layered:** the executor MUST iterate its own tests/lint/build to green inside
  the run (real, not narrated — Sonnet's Agent has Bash; `@coder` has `bash:allow`); then Opus (or
  GLM in panic) RE-runs verify as the gate before commit. Executor-green alone never authorizes a
  commit.
- **Review is never skipped.** Opus reviews the executor's diff in every Anthropic-alive mode — the
  guardrail replacing "Opus hand-types critical files." In panic, GLM self-reviews AND the human
  reviews at the commit gate.
- **Commit stays with a supervisor** (Opus, or the HUMAN in panic). No executor commits: Sonnet
  Agent is told "never commit"; `@coder` is `bash:allow` but prompt-forbidden from `git commit`,
  caught by the diff review.
- **Debug root-cause is judgment** (brain), never delegated blind — the executor only applies a fix
  the brain has diagnosed + directed.
- **Panic is Anthropic-quota-out** — it kills BOTH Opus AND Sonnet (shared subscription), so any
  Anthropic mode fails over to the GLM `brain` (opencode-go, or ollama on double-out), never to
  Sonnet. `ponytail:` a Sonnet-brain intermediate (Opus capped but Sonnet left) is out of scope —
  add only if the subscription ever meters them separately.

## Architecture Context (from the live repo, not memory)

- **SSOT repo (relocated):** `~/Drive-D/Projects/claude-plugin/model-router`. `install.sh`
  symlinks `bin/{gx,route,router-doctor}` → `~/.local/bin`, `hooks/{delegate,code-delegate}.sh`
  → `~/.claude/hooks`, `router.config.jsonc` → `~/.config/model-router`. **All those symlinks
  currently point at the OLD `~/Drive-D/Projects/model-router` path → dangling.**
- **`bin/gx`** hardcodes `opencode run … --agent executor -m "$MODEL"` (both start + continue).
  Model SSOT: `-m > $GX_MODEL > state file > opencode-go/deepseek-v4-pro`. Session-aware
  (per-repo pointer under `~/.local/state/gx/`).
- **`bin/route`** writes one line (the chosen profile's model) to `~/.config/model-router/state`.
  `router.config.jsonc` profiles: `default=opencode-go/deepseek-v4-pro`,
  `glm-heavy=ollama/glm-5.2:cloud`. `tiers.heavy.model=ollama/glm-5.2:cloud`.
- **`hooks/delegate.sh`** (PreToolUse on Skill): on `gaspol-execute|gaspol-parallel` it runs
  `route glm-heavy` (state→GLM) and injects a directive telling me to run
  `opencode run -m ollama/glm-5.2:cloud` — **single-model GLM. This is the bug's source.**
- **`hooks/code-delegate.sh`** (PreToolUse on Write|Edit): DENIES hand-edits of code files,
  tells me to route through `gx`. Bypass marker `~/.config/model-router/allow-direct-edit`.
- **`opencode.jsonc`** (global `~/.config/opencode/`, NOT yet in the repo): already holds the
  smoke config (`executor` glm `edit:deny` + `coder` deepseek). `opencode 1.17.11` supports
  per-agent `model`, `mode: primary|subagent|all`, and primary→subagent delegation via the
  built-in `task` tool (docs confirmed).

## Tech Stack

Bash (no arg-parsing lib — `gx` is a thin wrapper, ponytail), `opencode` CLI 1.17.11,
`opencode-go` provider (serves BOTH `glm-5.2` and `deepseek-v4-pro`), python3 for hook JSON,
Claude Code hooks (PreToolUse). No new dependency.

## Data Integration Map

| Component | File | Exists? | Action |
|---|---|---|---|
| Stale symlinks → gx/route/hooks | `install.sh` | Yes (relocated repo) | Re-run install.sh → relink to new path |
| Lead agent (GLM, edit:deny, delegates) | `opencode.jsonc` `agent.executor` | Yes (smoke config) | Finalize + version in repo + link |
| Coder agent (deepseek, mode:all) | `opencode.jsonc` `agent.coder` | Yes (smoke config) | Set `mode:all`, `edit:allow` |
| Failover lead (ollama GLM) | `opencode.jsonc` `agent.executor-ff` | No | Create: `ollama/glm-5.2:cloud`, edit:deny, delegates to `@coder-ff` |
| Failover coder (ollama kimi) | `opencode.jsonc` `agent.coder-ff` | No | Create: `ollama/kimi-k2.7-code:cloud`, mode:all, edit:allow |
| Solo vs team routing | `bin/gx` | Yes (`--agent executor` hardcoded) | Default `--agent coder`; add `--team` → executor + omit `-m` |
| Team + solo failover to ollama pair | `bin/gx` | Partial (solo retries `ollama/glm` single) | `--team` fail → retry `--agent executor-ff`; solo fail → `--agent coder-ff` |
| Panic brain (Opus subscription out) | `opencode.jsonc` `agent.brain`/`brain-ff` + `bin/route` panic | No | Create `brain` (GLM judgment+delegate, bash:deny); `route panic --run` → `--agent brain` |
| Session-start mode popup | `hooks/session-mode.sh` (SessionStart) + `~/.config/model-router/mode` marker | No | Hook prompts Claude → AskUserQuestion (anthropic-team[default] / anthropic-solo / opencode / ollama) → write marker + apply |
| Sonnet-5 executor (anthropic-team) | native Claude Code `Agent` tool (`model: sonnet`) | Yes (harness) | Opus spawns Sonnet Agent for codegen/TDD; reviews diff; commits. No opencode |
| Mode-aware delegate remedy | `hooks/code-delegate.sh` (`mode` marker) | Partial (bypass only) | anthropic-team→Sonnet Agent; anthropic-solo→allow; opencode/ollama→gx |
| gx honors chosen pool | `bin/gx` (`mode` marker) | No | `opencode`→executor/coder pair; `ollama`→executor-ff/coder-ff pair |
| execute/parallel → two-tier | `hooks/delegate.sh` | Yes (forces glm-heavy) | Nudge `gx --team`; drop force-glm + old invariant |
| plain code edit → solo | `hooks/code-delegate.sh` | Yes | Keep block; text → `gx` solo; drop invariant |
| heavy tier model | `router.config.jsonc` | Yes (`ollama/glm-5.2:cloud`) | → `opencode-go/glm-5.2`; drop cross-pool invariant |
| Stream events to chat | `bin/gx` (`--team` json) + Monitor | No | `--format json` unbuffered log + Monitor tail |
| Jalan-A doctrine | `~/.claude/CLAUDE.md`, repo `CLAUDE.md`/`README.md` | Yes | Sync 2-mode + edit:deny lever + drop invariant |

**Contract:** every "Yes" is edited in place (real file); the one "No" (streaming) is built as a
real json-log + Monitor tail, never a fake "pretend it streamed" note.

---

## Implementation Plan

### Phase 0 — Re-link the relocated tooling (PREREQUISITE)

**Est:** 3 min. **Files:** run `install.sh` (no edit). `~/.local/bin/{gx,route}`,
`~/.claude/hooks/*delegate.sh`, `~/.config/model-router/router.config.jsonc` get repointed.

**Steps:**
1. Write failing smoke: `cat ~/.local/bin/gx >/dev/null` → **currently fails** (`No such file`
   — dangling to old path). This is the RED.
2. Run `bash ~/Drive-D/Projects/claude-plugin/model-router/install.sh` (idempotent; backs up any
   real file as `*.bak.$$`).
3. Re-run the smoke: `cat ~/.local/bin/gx >/dev/null && echo OK` → GREEN.
4. `route default` → state = `opencode-go/deepseek-v4-pro`; `router-doctor` clean.

**Verification:**
- [ ] `readlink -f ~/.local/bin/gx` → `…/claude-plugin/model-router/bin/gx` (new path)
- [ ] `readlink -f ~/.config/model-router/router.config.jsonc` → new path
- [ ] `gx --print-model` prints a model (no dangling error)
- [ ] hooks resolve: `cat ~/.claude/hooks/delegate.sh >/dev/null` OK

### Phase 1 — Finalize + version the 2-agent opencode config

**Est:** 8 min. **Files:** Create `opencode.jsonc` in repo root; `install.sh` (link it);
verify against global `~/.config/opencode/opencode.jsonc`.

**Steps:**
1. Write failing smoke `tests/smoke_two_tier.sh` (new): runs
   `opencode run "create t_<rand>.py with foo()" --agent executor --format json` in a scratch git
   repo, asserts the event stream contains `"tool":"task"` AND `subagent`/`coder` AND
   `deepseek-v4-pro`. Expected RED reason: config not yet linked from repo / coder `mode` wrong.
2. Write `opencode.jsonc` in the repo: keep the `ollama` provider block (it defines
   `glm-5.2:cloud` + `kimi-k2.7-code:cloud` — the failover pair — plus offline qwen). Four agents:
   - `agent.executor` = `{mode:primary, model:"opencode-go/glm-5.2", permission:{edit:deny,
     bash:deny,webfetch:deny}, prompt:"<lead: delegate ALL impl to @coder via task, review, never
     commit>"}`
   - `agent.coder` = `{mode:all, model:"opencode-go/deepseek-v4-pro",
     permission:{edit:allow,bash:allow,webfetch:deny}, prompt:"<bulk coder, real code no
     placeholder; write AND RUN the tests to green; edit + run tests only; NEVER git commit/push>"}`.
     `bash:allow` because TDD needs a real test-runner (pytest/npm test); the "never commit" prompt +
     the diff-review gate (Opus/human sees any stray commit) is the guardrail — `ponytail:` tighten
     to a git-blocking bash wrapper only if a rogue commit ever actually happens.
   - `agent.executor-ff` = same as `executor` but `model:"ollama/glm-5.2:cloud"` and the prompt
     names its partner explicitly: "delegate ALL impl to **@coder-ff**" (so the failover lead never
     picks the dead-pool `@coder`).
   - `agent.coder-ff` = same as `coder` but `model:"ollama/kimi-k2.7-code:cloud"`.
   - `agent.brain` = `{mode:primary, model:"opencode-go/glm-5.2", permission:{edit:allow,
     bash:deny,webfetch:deny}, prompt:"<STANDALONE BRAIN — Claude/Opus is down. You OWN the
     judgment: reason through design + plan + review yourself, then delegate bulk coding to @coder,
     review its diff, iterate. You may edit a critical file directly. NEVER commit — leave the diff
     for the human operator to review + commit.>"}`. This is the Opus replacement (Decision B):
     GLM does judgment inline (degraded vs Opus) + drives the two-tier. `edit:allow` (unlike the
     narrow `executor`) because a brain sometimes edits; `bash:deny` keeps the commit gate human.
   - `agent.brain-ff` = same as `brain` but `model:"ollama/glm-5.2:cloud"` and prompt delegates to
     **@coder-ff** — only for the rare Opus-down AND opencode-go-down double failure.

   `ponytail:` `edit:deny` on both leads is the delegation lever (edit:allow made GLM code trivial
   tasks itself — proven). Two agent pairs (not one `-m` swap) because opencode pins a subagent's
   model in config — `-m` can't reach it. **TDD ownership (matrix):** only the coder tier has
   `bash:allow` (to run tests); leads + brains are `bash:deny` — they orchestrate + never commit.
   `coder-ff` mirrors `coder` (`bash:allow`); `executor(-ff)` + `brain(-ff)` stay `bash:deny`.
3. Add to `install.sh`: `link "$SRC/opencode.jsonc" "$HOME/.config/opencode/opencode.jsonc"`
   (backs up the current global file). Re-run `install.sh`.
4. Run the smoke → GREEN (GLM lead delegates to deepseek coder).
5. Solo smoke: `opencode run "create s_<rand>.py with bar()" --agent coder --format json` →
   asserts `"tool":"write"` by `deepseek-v4-pro`, **no** `task` (direct, no lead).
6. Failover smoke (manual, ollama signed-in): `opencode run "create f_<rand>.py with baz()"
   --agent executor-ff --format json` → asserts `task`→`coder-ff`→`kimi-k2.7-code` wrote the file
   (the failover pair delegates correctly). `ponytail:` we drive `-ff` directly here rather than
   simulate opencode-go token-exhaustion; Phase 2 wires the automatic retry.
7. Brain smoke: `opencode run "plan then implement a 2-func module" --agent brain --format json`
   → asserts the run both reasons (text steps) AND `task`→`coder`→`deepseek-v4-pro` wrote the code,
   and did NOT commit (no git/bash tool). Confirms the Opus-replacement path.

**Verification:**
- [ ] `tests/smoke_two_tier.sh` GREEN: task→coder→deepseek wrote the file
- [ ] solo run writes directly on deepseek, no delegation
- [ ] `executor-ff` delegates to `coder-ff` on kimi (failover pair works, distinct from primary)
- [ ] `brain` reasons + delegates to `@coder` + never commits (bash denied)
- [ ] global `opencode.jsonc` is a symlink to the repo file
- [ ] no placeholder/TODO in the prompts

### Phase 2 — `gx`: default solo, `--team` = two-tier

**Est:** 10 min. **Files:** `bin/gx`.

**Steps:**
1. Write failing smoke: `gx --team --print-model` and assert `gx` selects `--agent executor`
   with NO `-m` passed; `gx --print-model` (no flag) selects `--agent coder`. Expected RED:
   `--team` flag unknown, agent hardcoded `executor`.
2. Add `--team` to the arg loop (`TEAM=1`). Introduce `AGENT`: default `coder`; `--team` →
   `executor`. Replace the two hardcoded `--agent executor` in `run_start` + the continue branch
   with `--agent "$AGENT"`.
3. When `TEAM=1`: do NOT pass `-m` (let `opencode.jsonc` drive lead=glm + sub=deepseek). When
   solo: keep the existing `-m "$RES_MODEL"` (deepseek/flash/override). `ponytail:` a single
   `MFLAG_ARR` array — empty for team, `(-m "$RES_MODEL")` for solo — so both branches share one
   `opencode run` line.
4. **Failover retry to the ollama pair.** Generalize the existing start-failover: on a
   `run_start` failure when the tier is `opencode-go` (solo) OR always for `--team` (the team pair
   is opencode-go), retry ONCE on the failover AGENT, not a bare model:
   - `--team` → retry `--agent executor-ff` (ollama glm lead → `@coder-ff` kimi), still no `-m`.
   - solo → retry `--agent coder-ff` (ollama `kimi-k2.7-code:cloud`), replacing the old
     `-m ollama/glm-5.2:cloud` single-model failover.
   `ponytail:` failover trigger stays "opencode run exited non-zero on the opencode-go tier" — no
   token-count probing; refine only if false-triggers appear. Never failover an already-`-ff` run
   (no loop).
5. Update the `gx` header comment block: document `gx` (solo deepseek) vs `gx --team` (GLM lead →
   deepseek), and the failover pair (opencode token out → ollama glm + kimi). Drop the "GLM→ollama
   always" note; ollama is now the FAILOVER pool only.
6. Run smokes → GREEN.

**Verification:**
- [ ] `gx --team` → `--agent executor`, no `-m` in the opencode invocation (grep the echo/`set -x`)
- [ ] `gx` (default) → `--agent coder` + `-m opencode-go/deepseek-v4-pro`
- [ ] on a forced start failure: `--team` retries `--agent executor-ff`; solo retries `--agent
      coder-ff` (assert via a stubbed `opencode` that fails once, or the echoed failover line)
- [ ] `--new`, positional-file, `--end`, `--print-session`, continue all still work (regression)
- [ ] `shellcheck bin/gx` clean (or no new warnings)

### Phase 3 — Hooks + router.config + panic brain: nudge the right mode, drop the invariant

**Est:** 15 min. **Files:** `hooks/delegate.sh`, `hooks/code-delegate.sh`,
`router.config.jsonc`, `bin/route`.

**Steps:**
1. Write failing smoke: pipe a fake `gaspol-execute` Skill payload into `delegate.sh`, assert the
   injected `additionalContext` says **`gx --team`** and does NOT run `route glm-heavy` / name
   `opencode run -m ollama/glm-5.2:cloud`. Expected RED: current hook forces glm-heavy + single-`-m`.
2. `delegate.sh`: remove the `route glm-heavy` call + re-read; rewrite the directive → "big work:
   launch ONE `gx --team <spec>` (GLM-5.2 lead → deepseek `@coder` subagent, one opencode task);
   terima-beres review + commit." Drop the "GLM→ollama ONLY / deepseek→opencode-go ONLY" invariant
   line (both are opencode-go now); keep the 3-tier chain-of-command + "stay on Claude = 4 judgment
   skills + commit."
3. `code-delegate.sh`: keep the hard block; change the remedy text from `gx <spec>` (implicitly the
   old single executor) to explicitly **`gx "<brief>"` (deepseek solo)** for a plain small change,
   and mention `gx --team` for a multi-file feature. Drop the invariant line. Keep the bypass marker.
4. `router.config.jsonc`: `tiers.heavy.model` → `opencode-go/glm-5.2`; `profiles.glm-heavy` →
   `opencode-go/glm-5.2`. **Leave `profiles.failover-opencode` = `ollama/glm-5.2:cloud`** — ollama
   IS the failover pool (the `gx` `-ff` retry uses ollama). Update the top comment: drop "GLM→ollama
   ONLY … separate quota pools"; note the DEFAULT executor pool is `opencode-go` (both glm-5.2 +
   deepseek-v4-pro), the FAILOVER pool is `ollama` (glm-5.2 + kimi-k2.7-code), and the brain stays
   Anthropic. `panicBrain` stays `ollama/glm-5.2:cloud` — now the `brain-ff` model reference.
5. **`bin/route` panic → two-tier brain (Opus-down replacement).** Change the `panic --run` branch
   from `exec opencode run -m "$PB" "$@"` to `exec opencode run --agent brain "$@"` (GLM owns
   judgment + delegates coding to `@coder`). Change the printed escape from `opencode run -m $PB` to
   `opencode run --agent brain "<your task>"` + a second line `# opencode-go also down? → opencode
   run --agent brain-ff "<your task>"`. Update the panic comment: Opus-down → GLM full brain
   (judgment degraded to GLM, delegates coding, HUMAN commits — brain is bash:deny).
6. Run the hook + panic smokes → GREEN.

**Verification:**
- [ ] `delegate.sh` on execute/parallel emits `gx --team`, no `route glm-heavy`
- [ ] `code-delegate.sh` still DENIES a `.py` edit; remedy text names `gx` solo + `gx --team`
- [ ] `route glm-heavy` → state `opencode-go/glm-5.2` (not ollama)
- [ ] `route panic` prints `opencode run --agent brain …` (+ `brain-ff` fallback); `--run` execs it
- [ ] `router-doctor` clean; `route default` → deepseek-v4-pro
- [ ] no "GLM→ollama ONLY" invariant text remains in hooks/router.config

### Phase 4 — Stream executor events to chat (kill the silent run)

**Est:** 10 min. **Files:** `bin/gx` (team json log), `.gitignore` (ignore run logs).

**Steps:**
1. Write failing smoke: run `gx --team` on a 2-file task backgrounded; while it runs, assert its
   json event log GROWS incrementally (≥2 size samples increasing before exit), i.e. not a single
   end-of-run flush. Expected RED: default format block-buffers → log 0 bytes until exit (observed).
2. `gx --team`: write opencode's `--format json` to `${XDG_STATE_HOME:-~/.local/state}/gx/<repo>.jsonl`
   AND stdout (`tee`), prefixing the opencode call with `stdbuf -oL` (best-effort line-buffer).
   `ponytail:` if opencode still buffers (bun runtime ignores stdbuf), fall back to `opencode serve`
   + poll `/session/:id/message` — but only build that if the stdbuf smoke fails; note the upgrade
   path in a comment, don't pre-build it.
3. Orchestration contract (documented in the header + CLAUDE.md, not code): I run `gx --team`
   backgrounded, then `Monitor` tail the jsonl filtering `task|coder|deepseek|write|edit|error|done`
   → each event surfaces in chat live.
4. Run the smoke → GREEN (log grows mid-run) OR, if stdbuf fails, implement the serve fallback and
   re-run.

**Verification:**
- [ ] json event log grows incrementally during a >30s `gx --team` run (2 increasing size samples)
- [ ] a Monitor tail surfaces delegation + file-write events in chat before the run ends
- [ ] run logs are git-ignored (no repo footprint)

### Phase 5 — Doctrine sync + end-to-end + commit/push

**Est:** 12 min. **Files:** `~/.claude/CLAUDE.md` (Jalan-A section), repo `CLAUDE.md` +
`README.md`, then commit/push the repo.

**Steps:**
1. Write failing check: `grep -q "gx --team" ~/.claude/CLAUDE.md` → RED (not documented yet).
2. `~/.claude/CLAUDE.md` Jalan-A: rewrite to the 2-mode model — **solo** (`gx`, deepseek) for
   plain/small; **two-tier** (`gx --team`, GLM lead → deepseek `@coder`) for gaspol-execute/parallel;
   the `edit:deny` lever; the **failover pair** (opencode token out → `gx` retries the ollama pair:
   `executor-ff` glm-5.2 lead → `coder-ff` kimi-k2.7-code). **Drop** the "GLM→ollama ONLY,
   deepseek→opencode-go ONLY" invariant — replace with "DEFAULT executor pool = `opencode-go`
   (glm-5.2 lead + deepseek-v4-pro), FAILOVER pool = `ollama` (glm-5.2 lead + kimi-k2.7-code);
   Opus/Anthropic brain stays separate." Document the **panic brain** (Opus subscription out →
   session dies → operator runs `route panic --run` → `--agent brain`: GLM owns judgment
   [brainstorm/plan/review, degraded vs Opus] + delegates coding to `@coder`; `brain-ff` on
   ollama+kimi for the double failure; the HUMAN reviews + commits — `brain` is bash:deny).
3. Repo `CLAUDE.md`/`README.md`: same 2-mode summary + panic-brain + **the full ownership matrix**
   (who does brainstorm/plan/codegen/TDD/debug/verify/review/commit per mode) + **the session-start
   mode selector** (`mode` marker: anthropic-team[default]/anthropic-solo/opencode/ollama;
   anthropic-team = Opus brain + Sonnet-5 Agent executor) + the relocated-path note +
   `install.sh` now also links `opencode.jsonc` + `session-mode.sh`.
4. **End-to-end:** `route default`; run `gx --team` on a real 2-file scratch task → confirm
   task→coder→deepseek for both files, events streamed; run `gx` solo on a 1-file task → deepseek
   direct; `route panic` prints the `--agent brain` escape. Then a `.py` Edit attempt → still
   blocked by `code-delegate.sh`.
5. `git add -A && git commit` (conventional; Co-Authored-By trailer) `&& git push origin main` in
   the model-router repo. `graphify update .` if the repo tracks a graph (skip if none).

**Verification:**
- [ ] `~/.claude/CLAUDE.md` documents `gx --team` + 2-mode + edit:deny lever; no stale invariant
- [ ] end-to-end: team delegates (2 files via deepseek), solo is direct, code Edit still blocked
- [ ] `install.sh` re-run idempotent (only symlinks, backups on real files)
- [ ] committed + pushed; working tree clean

### Phase 6 — Session-start mode selector (choose up front, don't wait for token-out)

**Est:** 15 min. **Files:** `hooks/session-mode.sh` (new SessionStart hook), `bin/gx`,
`hooks/code-delegate.sh`, `install.sh`, plus a settings.json snippet for the operator.

**Why:** the failover/panic paths above are REACTIVE (trigger on token exhaustion). The operator
should also be able to CHOOSE the mode at session start — so a session never silently burns the
wrong pool. One marker `~/.config/model-router/mode` ∈ `anthropic-team | anthropic-solo | opencode
| ollama` drives it. **Default (unset) = `anthropic-team`** (Opus brain + Sonnet 5 executor —
cheapest Opus-brain option).

**Steps:**
1. Write failing smoke: with `mode` unset, `bash hooks/session-mode.sh <<<'{}'` should emit a
   SessionStart `additionalContext` instructing Claude to ASK the operator their mode via
   AskUserQuestion, pre-selecting `anthropic-team`. Expected RED: hook doesn't exist.
2. `hooks/session-mode.sh` (SessionStart): read the `mode` marker (default `anthropic-team`); inject
   context = "Executor mode = `<mode>`. On turn 1, confirm/change it via AskUserQuestion:
   **Q1 Brain — Anthropic (Opus) [default] or Multi-modal (GLM)? Q2 Executor — if Anthropic:
   Sonnet 5 [default, = anthropic-team] or Opus-solo [anthropic-solo]; if Multi-modal: Opencode-go
   [opencode] or Ollama [ollama].** Write the chosen value to `mode` + apply." The hook only PROMPTS
   (cannot pop a dialog); Claude runs AskUserQuestion on turn 1, pre-selecting the recommended
   `anthropic-team`.
3. Define the marker→state mapping Claude applies after the popup (documented in the hook context +
   CLAUDE.md, executed by Claude):
   - `anthropic-team` (DEFAULT) → `rm -f allow-direct-edit`; code-delegate remedy = "spawn a Sonnet
     Agent" (Phase 6.5). Opus does NOT hand-edit; it delegates codegen to a Sonnet-5 Agent-tool
     subagent, reviews the returned diff, commits. No `gx`, no opencode.
   - `anthropic-solo` → `touch ~/.config/model-router/allow-direct-edit` (bypass ON: Opus codes
     directly). No delegation.
   - `opencode` → `rm -f allow-direct-edit`; `route default` (deepseek). `gx`/`gx --team` use the
     `opencode-go` pair; failover → ollama pair.
   - `ollama` → `rm -f allow-direct-edit`; write `mode=ollama`. `gx --team` uses `executor-ff` +
     `gx` solo uses `coder-ff` as PRIMARY (ollama glm+kimi); failover → opencode pair.
4. `bin/gx`: read the `mode` marker → pick the primary pair. `opencode`/unset → `executor`+`coder`
   (failover `-ff`); `ollama` → `executor-ff`+`coder-ff` (failover to `executor`+`coder`). `gx` is
   irrelevant in the anthropic-* modes (Opus/Sonnet don't use it).
   `ponytail:` a single `POOL` var chooses the pair + its failover partner — no new flags beyond
   `--team`.
5. `hooks/code-delegate.sh` becomes **mode-aware** (reads the `mode` marker), giving the right
   remedy when it blocks a code Edit/Write:
   - `anthropic-solo` → the bypass marker is set → exits 0 (Opus edits directly).
   - `anthropic-team` (DEFAULT) → DENY + remedy = "delegate to a Sonnet-5 executor: `Agent`
     tool, `subagent_type: general-purpose`, `model: sonnet`, prompt = the spec + gate (implement +
     write&run tests to green, no placeholder, DON'T commit); then review the returned diff +
     commit." (NOT gx — this mode is pure Anthropic.)
   - `opencode`/`ollama` → DENY + remedy = "route through `gx` / `gx --team`" (as today).
   `ponytail:` one `case "$mode"` picks the remedy string; the block logic (deny on code files
   unless bypass) is unchanged.
6. `install.sh`: `link "$SRC/hooks/session-mode.sh" "$HOOK_DIR/session-mode.sh"`. Print the
   settings.json SessionStart registration snippet for the operator to paste (the agent does NOT
   edit settings.json — §13.5).
7. Run the smokes → GREEN.

**Verification:**
- [ ] `session-mode.sh` on unset mode emits the "ask the operator" directive, pre-selecting `anthropic-team`
- [ ] AskUserQuestion flow sets the right state: `anthropic-team` → code-delegate remedy names the
      Sonnet Agent (no gx); `anthropic-solo` → bypass marker set (direct edits); `opencode`/`ollama`
      → gx uses the matching pair
- [ ] `code-delegate.sh` on a `.py` edit: `anthropic-team` remedy = Sonnet Agent; `opencode` remedy = gx
- [ ] `gx --team` honors `mode=ollama` (uses `executor-ff`) vs `mode=opencode` (uses `executor`)
- [ ] operator settings.json snippet documented (agent did not self-edit settings.json)
- [ ] choosing a mode at session start never requires waiting for a token-exhaustion failover

## Out of scope (documented)

- **opencode `serve` + SSE streaming** — only built if Phase 4's `stdbuf` line-buffer smoke fails
  (upgrade path noted in `gx`, not pre-built). `ponytail`.
- **Per-task cost caps / budget** — the two-tier costs ~2× round-trips; the `mechanical` profile
  (deepseek-flash solo, bypasses the lead) already covers pure rename/i18n. No new budget logic.
- **auto-selecting team vs solo from task size** — the mode is chosen by the trigger (execute/parallel
  hook → team; plain edit → solo) + my judgment, not a heuristic. YAGNI.
- **panic brain quality** — GLM doing brainstorm/plan/review is DEGRADED vs Opus (Decision B,
  accepted); we do NOT try to match Opus judgment. The panic brain also can't invoke the actual
  gaspol Claude-Code skills (they're a Claude plugin) — its prompt bakes in a condensed judgment
  doctrine inline. Human still reviews + commits (bash:deny). Not a gap to "fix", a documented ceiling.
