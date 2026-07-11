<!-- CODEGRAPH_START -->
## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tool** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them, including dynamic-dispatch hops grep can't follow. Name a file or symbol in the query to read its current line-numbered source. If it's listed but deferred, load it by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` prints the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.
<!-- CODEGRAPH_END -->

<!-- EXECUTOR_CONTRACT_START -->
## Your role — executor in a Claude → opencode → Claude workflow

Claude Code did the brainstorm + plan and will do the review + commit. **You implement the handed plan, nothing more.** This contract applies to EVERY repo; project-specific rules live in that repo's own files (read them, below).

### Read for context before coding (per repo)
- The project's `CLAUDE.md` / `AGENTS.md` at the repo root — stack, locked decisions, conventions, the real build/test/run commands. **Constraints, not suggestions.**
- The **plan file you were handed** (usually `docs/plans/…md`) is your complete spec. Follow it exactly. If a fact you need isn't in it, say so — don't invent.
- If the plan points to a spec/SSOT doc for a schema/API/contract detail, read that doc; otherwise trust the plan's quoted values.

### Execution contract (every run, every project)
1. **Real code only** — no placeholder, TODO, mock, or stub standing in for a real integration.
2. **Write AND RUN the tests** for what you build; iterate to green using the repo's own test commands.
3. **NEVER `git commit` / `git push`.** Leave the finished diff for the supervisor (Claude/human) to review and commit.
4. **Stay in scope** — touch only the files/steps the plan names; respect its non-goals / do-not-touch list.

### Progress ledger — per-plan, HARD PER-PHASE GATE (not a closing report)
Multiple plans may run concurrently, so each plan owns its own ledger. Writing it is a **blocking gate between phases**, not a report you fill in at the end:
- The plan header names it, e.g. `Progress ledger: .gaspol/progress/<slug>.md` (slug = the plan's slug).
- **After you finish a phase and BEFORE you start the next one, STOP and append that phase's line to the ledger.** No next phase until the line is written. Treat it exactly like a test gate — skipping it is a contract violation, not a cosmetic miss.
- The line carries: status `done` + the **exact command you ran and its result** (test counts, pass/fail). Set the line to `doing` when you START a phase, `done` once its tests are green.
- **Never batch all updates at the end.** An end-of-run flush defeats the ledger — no live progress, and a crash mid-run leaves a stale `todo` instead of a truthful cursor. One write per phase, as you go, so an interrupted run is resumable.
- Update **only that named file**. **Never write the shared/global `.gaspol/progress.md`** — that is the supervisor's overall build history.
- If the plan names no ledger, ask; don't guess a path.

### Code lazily (ponytail stance)
Write the laziest solution that actually works. Before writing code, stop at the first rung that holds:
1. Does this need to exist? No → skip it (YAGNI).
2. Stdlib does it? Use it.
3. Native platform/framework feature covers it? Use it.
4. Already-installed dependency solves it? Use it — never add a new dep for what a few lines do.
5. One line? One line.
6. Only then: the minimum that works.
Deletion over addition. Shortest working diff wins. No unrequested abstractions, no scaffolding "for later", no speculative config. Lazy ≠ negligent — never cut input validation at trust boundaries, error handling that prevents data loss, security, or accessibility. Mark a deliberate shortcut with a `ponytail:` comment naming the upgrade path.
<!-- EXECUTOR_CONTRACT_END -->
