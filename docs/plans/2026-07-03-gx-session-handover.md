# gx session-based handover — stop authoring a throwaway spec per handover

> Design doc (gaspol-brainstorm, 2026-07-03). Targets the `model-router` repo (`bin/gx`) +
> the global Jalan-A note in `~/.claude/CLAUDE.md`. `gaspol-plan` appends the Implementation
> Plan below.

## Design

### Problem

Every time Opus (brain) hands a task to the `gx` executor (GLM-5.2 / deepseek-v4-pro), the
current habit is to **author a fresh `.md` handover spec** and pass it to `gx`. Proven waste,
straight from `opencode session list` this morning: 7+ separate executor sessions, one per
scratch file — `.glm-modal-v2.md`, `.glm-modal-lightbox.md`, `.glm-modal-fix.md`,
`.gx-frame-thumb.md`, … Each spawned a **brand-new, amnesiac** executor session, so the brain
re-typed the same context every handover.

Two distinct wastes hide in that list:

1. **Redundant-with-the-plan** (`-v2` = initial build). The execution spec *already exists* —
   it's the `docs/plans/YYYY-MM-DD-<topic>.md` that gaspol-brainstorm + gaspol-plan already
   wrote (Design + Implementation Plan + Data Integration Map + per-phase verification). The
   scratch handover file is a pure duplicate of it.
2. **Re-spec on every iterative fix** (`-fix`, `-lightbox`). A follow-up defect ("the modal
   you built has bug X") was written as a NEW file → a NEW amnesiac session. The executor had
   just built the thing but was made to forget it and re-read intent.

### Root cause

`gx` is **stateless**: it always calls `opencode run` with no `-s`, so opencode mints a fresh
session each call (`bin/gx` today: `opencode run "$PROMPT" --agent executor -m "$1" -f "$SPEC"`).
The handover `.md` is a symptom of two things — a wrapper that requires a file, and a habit of
condensing the plan into a throwaway. `opencode run` itself already supports everything we need:
inline messages, `-s <session_id>`, `-c/--continue`, `--title`, `session list --format json`.

### Fix (Path 2 — locked with the user)

**Initial build: point gx at the existing plan file. Never author a separate handover `.md`.**
`gx docs/plans/<plan>.md "<gate>"` works *today* — `gx` already attaches any real in-repo file
via `-f`. The plan file is inside the repo (satisfies the `external_directory` gotcha) and IS
the spec.

**Iterative fixes: continue the same executor session with a short delta.** The plan describes
*intent*; the executor's own session remembers *what it actually built* — strictly better for
defect-fixes. First handover starts a task session; every follow-up is
`gx "X still red, fix only that"` — no file, no re-spec.

Together this removes both wastes and writes **zero** files into the repo.

### Mechanism — persistent per-task executor session

- **Session identity = the plan.** On a start, gx tags the session `--title "gx:<plan-slug>"`
  (`<plan-slug>` = plan basename minus `.md`). Robust capture: read it back by exact title from
  `opencode session list --format json` (survives interleaving — no "newest wins" race).
- **Active-session pointer, per-repo, OUTSIDE the repo.** Store the resolved `ses_id` + model in
  `${XDG_STATE_HOME:-$HOME/.local/state}/gx/<repo-hash>.session` (`<repo-hash>` = first 12 of
  `shasum` of `git rev-parse --show-toplevel`). Zero repo footprint; lets a bare `gx "delta"`
  continue with no arguments. (The `external_directory` gotcha is about the *spec/target* opencode
  reads — gx's own state file is unaffected by living under `~/.local/state`.)
- **Continue.** Bare `gx "<delta>"` (no file arg) reads the pointer and runs
  `opencode run "<delta>" --agent executor -m <stored-model> -s <ses_id>`. Same model as the
  session (router invariant: one model per session — deepseek↔opencode-go, GLM↔ollama, never
  crossed mid-thread).

### Planless handover (ad-hoc change, no `docs/plans/*.md`)

Per the global Jalan-A rule, **any** substantive code change delegates — including a plain
"tambahkan fitur X" / "fix bug Y" that never went through gaspol-plan, so there is no plan file.
A planless task's brief is, by definition, **small** (if it were big/multi-phase you'd have
written a plan). So the brief goes **inline**, no file authored:

```
gx --new "add debounce to the search input in SearchBar.vue; gate: test green, no placeholder, don't commit"
gx --new - <<'EOF'      # multiline brief without a file (shell-escape escape hatch)
<paste a few-paragraph brief here>
EOF
```

`--new`'s argument is now **polymorphic**: an existing file path → attach via `-f` (the plan
path); `-` → read the brief from stdin; any other string → the inline brief (sent as the start
message, no `-f`). Session title derives accordingly: file → `gx:<basename>`; inline/stdin →
`gx:adhoc-<HHMMSS>` (bash `date`, unique enough for serial use). Iteration is identical to the
planned path — `gx "delta"` continues the same session. So planless work gets continuity too,
and still writes **zero** files.

Truly trivial, already-reviewed one-liners stay on the brain (unchanged Jalan-A carve-out) — this
covers *substantive* planless changes.

### gx interface (after patch)

```
gx docs/plans/<plan>.md ["gate msg"]   # START task session from a PLAN FILE: attach, tag title, capture+store ses_id
                                       #   (legacy positional-file form — unchanged muscle memory, now also stores the session)
gx --new <plan.md> ["gate msg"]        # explicit reset from a plan file (force fresh even if one active)
gx --new "<inline brief + gate>"       # START a PLANLESS session from an inline brief (no file)
gx --new -  <<'EOF' … EOF              # START planless from a multiline stdin brief (no file)
gx "delta msg"                         # CONTINUE active session with a delta (no file). Errors if none active.
gx --end                               # clear the active-session pointer (task done)
gx --print-session                     # echo the active ses_id (debug)
gx --print-model                       # unchanged
gx -m <provider/model> …               # unchanged; on start, pins the session's model
```

Disambiguation reuses gx's existing rule with one addition: a first arg (or `--new` arg) that is
an **existing file** → spec/plan (start, `-f`); `-` → stdin brief (start, inline); any other
non-flag string when **no session is active** → an inline start brief; any string when a session
**is** active → a continue delta. `--new` forces start; `--end` / `--print-session` are explicit
overrides.

### Behavior details / decisions

- **Legacy `gx <file>` still starts+stores** so the PreToolUse delegate hooks and old habits keep
  working — they just gain continuity for free.
- **Capture-by-title, not newest.** `jq -r --arg t "gx:<slug>" '[.[]|select(.title==$t)]|.[0].id'`
  — robust even if another gx runs between start and capture.
- **Failover only on start.** The existing opencode-go → `ollama/glm-5.2:cloud` single-retry
  failover stays on `--new`/start. A *continue* that fails does NOT failover (continuing a
  deepseek thread on GLM mid-session is incoherent) — it errors and tells the user to `--new` on
  the other tier. `# ponytail: continue-failover left out; add only if continues prove flaky.`
- **No new dependency.** jq is already at `/usr/bin/jq`; `shasum` is macOS-native.

### Data Integration Map

| Component | Data Source | Existing? | Notes |
|-----------|-------------|-----------|-------|
| model resolution | `-m` > `$GX_MODEL` > router state-file > default | ✓ | unchanged |
| execution spec (planned) | `docs/plans/<plan>.md` (already authored) | ✓ | replaces the throwaway handover `.md` |
| execution spec (planless) | inline `--new "<brief>"` or `--new -` stdin | new | small ad-hoc task, no file authored |
| session capture | `opencode session list --format json` | ✓ CLI | jq select by `title=="gx:<slug>"` |
| session continue | `opencode run -s <ses_id>` | ✓ CLI | new usage inside gx |
| active pointer | `~/.local/state/gx/<repo-hash>.session` (`ses_id\tmodel`) | new | per-repo, outside repo |
| failover | `ollama/glm-5.2:cloud` single retry | ✓ | start-only now |

### Artifacts touched

1. **`~/Drive-D/Projects/model-router/bin/gx`** — patch: `--new`/`--end`/`--print-session`,
   polymorphic start arg (plan file `-f` / `-` stdin brief / inline brief), per-repo state file,
   title-tag + id-capture on start, delta-continue on no-file, model pinned per session. Keep
   model-resolution + start-failover intact.
2. **`~/.claude/CLAUDE.md`** — the global "Codegen delegation — Jalan A" block: replace "write the
   whole-task spec to an in-repo `.md`" with the branch **"plan exists → hand gx that
   `docs/plans/<plan>.md`; planless small change → `gx --new \"<inline brief+gate>\"` (or `--new -`
   multiline); never author a separate handover `.md`"**, and document the start→delta→end flow.
3. **memory `execute-terima-beres-mode`** — nuance: handover uses a persistent executor session
   keyed to the plan file; follow-ups are deltas, not new files. (Still terima-beres: brain
   reviews the accumulated diff + commits.)
4. **`~/Drive-D/Projects/model-router/scripts/test-gx-routing.sh`** — one runnable self-check: stub
   `opencode` on PATH, assert (a) file-arg start calls `--title gx:…` + writes the pointer, (b)
   no-file call reads the pointer and passes `-s <id>`, (c) `--end` clears it, (d) no-file with no
   active pointer exits non-zero. No bats/framework — plain `set -e` + asserts.

### Ceilings (ponytail-honest)

- Title collision (two plans same basename) → newest match wins. Plan names are date-prefixed, so
  rare. `# ponytail:` upgrade to a UUID suffix only if it bites.
- Serial-use assumption. Parallel `gaspol-parallel` lanes each want their OWN session anyway
  (distinct plan slugs) — the per-repo single pointer means parallel lanes must pass an explicit
  plan/`--session`; out of scope here (bulk-parallel is a separate flow).
- A stale pointer (task abandoned without `--end`) is harmless: the next `--new` overwrites it; a
  bare `gx "delta"` against a dead session surfaces opencode's own error.

### Non-goals

- No change to model routing, the router plugin, or the PreToolUse delegate hooks' matcher logic.
- No fileless *first brief* requirement — the plan file is the first brief and that's fine; the
  win is not authoring a *second, redundant* file.
- Not touching the anthropic brain/subagent path (Jalan-A invariant: only the executor is
  multi-model).

---

## Implementation Plan

> **For Claude:** REQUIRED SKILL: Use gaspol-execute to implement this plan.
> **CRITICAL:** This plan patches real tooling (`bin/gx`) + real CLI calls (`opencode`). During
> execution, NEVER substitute placeholders. If `opencode session list --format json` shape
> differs from what the test stub assumes, STOP and re-probe the live CLI — don't guess.

### Goal

Make `gx` session-aware so a handover to the executor **reuses the plan file (or an inline
brief) instead of authoring a throwaway `.md`**, and **continues the same executor session** for
iterative fixes instead of spawning a fresh amnesiac one. Removes both wastes proven in the
`opencode session list` history (redundant-with-plan + re-spec-per-fix), for both planned and
planless work, writing zero files into the repo.

### Architecture Context

- **`bin/gx`** (`~/Drive-D/Projects/model-router/bin/gx`, symlinked `~/.local/bin/gx`) — thin
  bash wrapper. Today: model-resolution (`-m` > `$GX_MODEL` > router state-file > default),
  requires a spec FILE, `opencode run "$PROMPT" --agent executor -m "$1" -f "$SPEC"`, opencode-go
  → `ollama/glm-5.2:cloud` single-retry failover. All of this stays.
- **opencode CLI** — `run [message..]` (positional message array; `-s/--session`, `-c`,
  `--title`, `-f`), `session list --format json` → `[{id,title,updated},…]` newest-first.
- **Global Jalan-A note** — `~/.claude/CLAUDE.md`, "Codegen delegation — Jalan A" block.
- **Memory** — `~/.claude/projects/-Users-alisadikin-Drive-D-Projects-indusia-visual-editor/memory/execute-terima-beres-mode.md`.
- **jq** `/usr/bin/jq`, `shasum` native — no new dependency.

### Tech Stack

Bash (`set -euo pipefail`, existing gx style — no getopts lib, ponytail thin-wrapper), jq for the
session-list parse, `shasum` for the per-repo state key. Self-test is plain bash + `set -e` +
asserts with a stubbed `opencode`/`git` on `PATH` (no bats).

### Data Integration Map

| Feature | Data Source | API/CLI | Exists? | Action |
|---------|-------------|---------|---------|--------|
| model resolution | `-m` > `$GX_MODEL` > `~/.config/model-router/state` > default | in-gx | Yes | Use existing, unchanged |
| planned spec | `docs/plans/<plan>.md` | `opencode run -f` | Yes | Attach directly (no new file) |
| planless spec | inline `--new "<brief>"` / `--new -` stdin | `opencode run "<msg>"` | No | Add to gx (inline start message) |
| session capture | `opencode session list --format json` | jq select `title=="gx:<slug>"` | Yes (CLI) | New usage in gx |
| session continue | active `ses_id` | `opencode run -s <id>` | Yes (CLI) | New usage in gx |
| active pointer | `${XDG_STATE_HOME:-$HOME/.local/state}/gx/<repo-hash>.session` (`ses_id\tmodel`) | file r/w | No | Create in gx |
| start failover | `ollama/glm-5.2:cloud` | `opencode run` retry | Yes | Keep, start-only |

### Phase A: Routing self-test harness (failing test first)

**Estimated time:** 10 min

**Files:**
- Create/Test: `~/Drive-D/Projects/model-router/scripts/test-gx-routing.sh`

**Steps:**
1. Write failing test for gx session routing. The test creates a temp `PATH` dir with stub
   `opencode` (logs every arg to `$OUT/opencode.args`; `session list --format json` echoes a
   canned `[{"id":"ses_TESTFAKE","title":"gx:<expected-slug>","updated":1}]`) and a stub `git`
   (`rev-parse --show-toplevel` → a temp repo dir), points `XDG_STATE_HOME` at a temp dir, then
   asserts:
   - **A1** `gx --new <tmpfile.md> "gate"` → `opencode.args` contains `--title gx:<basename>`,
     `-f <tmpfile.md>`, `-s` ABSENT; pointer file exists and contains `ses_TESTFAKE`.
   - **A2** `gx "delta text"` (pointer active) → args contain `-s ses_TESTFAKE`, `-f` ABSENT,
     message == `delta text`.
   - **A3** `gx --new "inline brief"` (no file) → args contain `--title gx:adhoc-`, message ==
     `inline brief`, `-f` ABSENT.
   - **A4** `gx --end` → pointer file removed.
   - **A5** bare `gx "delta"` with NO pointer → exit code non-zero, stderr mentions `--new`.
   Expected error on first run: assertions fail / non-zero exit — `gx: butuh spec file` from the
   current unpatched gx (no `--new`/`-s`/pointer support yet).
2. Run `bash scripts/test-gx-routing.sh`, confirm it FAILS for the expected reason (current gx has
   no session support).

**Verification:**
- [ ] `scripts/test-gx-routing.sh` exists, is executable, runs hermetically (stubs on `PATH`,
      `XDG_STATE_HOME` sandboxed — no real opencode call, no real repo state touched)
- [ ] Test fails against the current unpatched `bin/gx` (proves it exercises new behavior)
- [ ] No placeholder/TODO in the test; stub `opencode` handles BOTH `run` and `session list`
- [ ] Commit: `test(gx): routing self-test for session start/continue/end`

### Phase B: Patch `bin/gx` — start / continue / end (make green)

**Estimated time:** 15 min

**Files:**
- Modify: `~/Drive-D/Projects/model-router/bin/gx`

**Steps:**
1. Confirm Phase A test is red. Add flag parsing: `--new`, `--end`, `--print-session` (alongside
   existing `-m`, `--print-model`). Compute `STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/gx"`,
   `REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`,
   `PTR="$STATE_DIR/$(printf %s "$REPO" | shasum | cut -c1-12).session"` (`mkdir -p "$STATE_DIR"`).
2. Implement `--end`: `rm -f "$PTR"`; exit 0. Implement `--print-session`:
   `[[ -s "$PTR" ]] && cut -f1 "$PTR"`; exit.
3. Implement START (a real file first-arg, OR `--new <arg>`): resolve model as today; derive
   `SLUG` = plan basename-minus-`.md` for a file, else `adhoc-$(date +%H%M%S)`; build
   `run_start()` = `opencode run "$PROMPT" --agent executor -m "$MODEL" --title "gx:$SLUG"` **plus**
   `-f "$SPEC"` only when a file (skip `-f` for inline/`-`; for `-` read stdin into `$PROMPT`).
   Keep the existing start-failover wrapper. After a successful start, capture the id by title:
   `SID=$(opencode session list --format json | jq -r --arg t "gx:$SLUG" '[.[]|select(.title==$t)]|.[0].id')`
   and write `printf '%s\t%s\n' "$SID" "$MODEL" > "$PTR"`.
4. Implement CONTINUE (no file arg, non-flag message, pointer exists): read `SID`/`MODEL` from
   `$PTR`; `opencode run "$*" --agent executor -m "$MODEL" -s "$SID"` (NO `-f`, NO failover —
   `# ponytail: continue-failover omitted; add if continues prove flaky`). No active pointer →
   `echo "gx: no active session — start with: gx --new <plan.md|\"brief\">" >&2; exit 2`.
5. Preserve the legacy positional-file form (`gx <file> [msg]` with no `--new`) as an alias for
   START (so delegate hooks + muscle memory keep working, now storing the session).
6. Run `bash scripts/test-gx-routing.sh`, confirm all A1–A5 PASS. Run `bash -n bin/gx` (syntax).

**Verification:**
- [ ] `bash -n bin/gx` clean; `scripts/test-gx-routing.sh` green (A1–A5)
- [ ] Model resolution + start-failover paths unchanged (a start on `opencode-go/*` still failovers)
- [ ] Real behavior, no stub leakage: `gx --print-session` in a real repo after a `--new` echoes a
      `ses_…` id (spot-check against live opencode — one real `--new` on a throwaway `/tmp`-external
      note INSIDE this repo, then `--end`)
- [ ] No placeholder/TODO; `ponytail:` note present on the omitted continue-failover
- [ ] Commit: `feat(gx): session-based handover — reuse plan/inline brief, continue on delta`

### Phase C: Docs sync — global CLAUDE.md + memory (brain, no delegate)

**Estimated time:** 8 min

**Files:**
- Modify: `~/.claude/CLAUDE.md` (Jalan-A block)
- Modify: `~/.claude/projects/-Users-alisadikin-Drive-D-Projects-indusia-visual-editor/memory/execute-terima-beres-mode.md`

**Steps:**
1. In `~/.claude/CLAUDE.md`, in the "Codegen delegation — Jalan A" section, replace the
   "write the whole-task spec to an in-repo `.md`" guidance with the branch: **plan exists → hand
   gx the existing `docs/plans/<plan>.md`; planless substantive change → `gx --new "<inline
   brief+gate>"` (or `--new -` for multiline); iterative fix → `gx "<delta>"` continues the same
   session; `gx --end` closes. NEVER author a separate handover `.md`.** Keep everything else.
2. Update memory `execute-terima-beres-mode.md`: add that handover now uses a persistent
   per-task executor session keyed to the plan file / inline brief; follow-ups are deltas, not new
   files (still terima-beres: brain reviews the accumulated diff + commits). Refresh the one-liner
   in `MEMORY.md` if the hook changes.
3. `grep -n "gx --new\|gx \"" ~/.claude/CLAUDE.md` to confirm the new flow text landed.

**Verification:**
- [ ] `~/.claude/CLAUDE.md` Jalan-A block documents start→delta→end + the no-separate-file rule;
      no leftover "write the whole-task spec to an in-repo `.md`" instruction
- [ ] memory `execute-terima-beres-mode.md` reflects session-continuity; `MEMORY.md` index line
      still accurate
- [ ] Grep confirms the new commands present
- [ ] Commit: `docs(jalan-a): plan-file/inline handover + gx session continuity`

### Delegation note (for gaspol-execute)

- **Phase A + B** (bash test + gx patch) are executor-eligible — but this is the meta-tool itself,
  small, and the brain has full `bin/gx` context; the edit-only `gx` executor also can't run the
  bash self-test. Either the brain implements A/B directly, or ONE autonomous `opencode run` does
  A+B to green. Bootstrap uses the CURRENT (file-based) gx — the new flow doesn't exist yet.
- **Phase C** (docs: CLAUDE.md + memory) stays on the brain per the Jalan-A carve-out (docs/config
  are not delegated).

### Red-flag self-check

- Data Integration Map present ✓ · every phase has Verification ✓ · CLAUDE.md/gx source read ✓ ·
  data sources concrete (exact CLI flags, exact pointer path) ✓ · TDD test-first in Phase A ✓ ·
  no phase >15 min ✓ · no placeholder language ✓.
