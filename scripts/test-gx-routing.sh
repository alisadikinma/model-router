#!/usr/bin/env bash
# Self-test for gx session routing (start / continue / end).
# Hermetic: stubs `opencode` + `git` on PATH, sandboxes XDG_STATE_HOME — no real
# opencode call, no real repo state touched. jq/shasum/date stay real.
#
# Asserts:
#   A1  gx --new <file> "gate"   → run has --title gx:<basename> + -f <file>, no -s; pointer stored w/ ses_TESTFAKE
#   A2  gx "delta"  (active)     → run has -s ses_TESTFAKE, no -f, message == delta
#   A4  gx --end                 → pointer removed
#   A5  gx "delta"  (no pointer) → non-zero exit, stderr mentions --new
#   A3  gx --new "inline brief"  → run has --title gx:adhoc-, message == brief, no -f
#
# Run against the UNPATCHED bin/gx it fails (no --new/-s/pointer support) — that is the RED gate.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GX="$HERE/../bin/gx"
[[ -f "$GX" ]] || { echo "FATAL: gx not found at $GX" >&2; exit 3; }

OUT="$(mktemp -d)"; export GX_TEST_OUT="$OUT"
export GX_TEST_REPO="$OUT/repo"; mkdir -p "$GX_TEST_REPO"
export XDG_STATE_HOME="$OUT/xdgstate"
STUB="$OUT/stub"; mkdir -p "$STUB"
trap 'rm -rf "$OUT"' EXIT

# --- stub opencode: log args, persist last --title, answer `session list` by that title ---
cat > "$STUB/opencode" <<'STUB_OC'
#!/usr/bin/env bash
O="$GX_TEST_OUT"
printf '%s\n' "$@" >> "$O/opencode.args"
cmd="${1:-}"; shift || true
case "$cmd" in
  run)
    prev=""
    for a in "$@"; do
      [[ "$prev" == "--title" ]] && printf '%s' "$a" > "$O/last_title"
      prev="$a"
    done
    exit 0 ;;
  session)   # `session list --format json`
    t="$(cat "$O/last_title" 2>/dev/null || echo gx:unknown)"
    printf '[{"id":"ses_TESTFAKE","title":"%s","updated":1}]\n' "$t"
    exit 0 ;;
  *) exit 0 ;;
esac
STUB_OC
chmod +x "$STUB/opencode"

# --- stub git: rev-parse --show-toplevel → repo; anything else → no-op ---
cat > "$STUB/git" <<'STUB_GIT'
#!/usr/bin/env bash
[[ "${1:-}" == "rev-parse" && "${2:-}" == "--show-toplevel" ]] && { echo "$GX_TEST_REPO"; exit 0; }
exit 0
STUB_GIT
chmod +x "$STUB/git"

run_gx() { PATH="$STUB:$PATH" bash "$GX" "$@"; }
clear_args() { : > "$OUT/opencode.args"; }
ptr_file() { find "$XDG_STATE_HOME/gx" -name '*.session' 2>/dev/null | head -1; }

FAIL=0
ok()   { echo "PASS: $1"; }
bad()  { echo "FAIL: $1" >&2; FAIL=1; }
has()  { grep -qxF -- "$2" "$OUT/opencode.args" && ok "$1" || bad "$1 (missing line: $2)"; }
absent(){ grep -qxF -- "$2" "$OUT/opencode.args" && bad "$1 (unexpected line: $2)" || ok "$1"; }

TMPMD="$GX_TEST_REPO/my-plan.md"; echo "# plan" > "$TMPMD"

# A1 — start from a plan file
clear_args
run_gx --new "$TMPMD" "gate: green" >/dev/null 2>&1
has    "A1 title tagged"        "--title"
has    "A1 title slug"          "gx:my-plan"
has    "A1 attaches plan file"  "$TMPMD"
absent "A1 no -s on start"      "-s"
P="$(ptr_file)"
if [[ -n "$P" ]] && grep -q "ses_TESTFAKE" "$P"; then ok "A1 pointer stored"; else bad "A1 pointer stored (file=$P)"; fi

# A2 — continue with a delta (pointer active)
clear_args
run_gx "delta text here" >/dev/null 2>&1
has    "A2 continues session"   "-s"
has    "A2 session id"          "ses_TESTFAKE"
has    "A2 delta message"       "delta text here"
absent "A2 no -f on continue"   "-f"

# A4 — end clears the pointer
run_gx --end >/dev/null 2>&1
[[ -z "$(ptr_file)" ]] && ok "A4 pointer cleared" || bad "A4 pointer cleared"

# A5 — continue with no active pointer errors out
clear_args
if run_gx "orphan delta" >/dev/null 2>"$OUT/err"; then
  bad "A5 exits non-zero"
else
  ok "A5 exits non-zero"
fi
grep -q -- "--new" "$OUT/err" && ok "A5 stderr mentions --new" || bad "A5 stderr mentions --new"

# A3 — start planless from an inline brief (no file)
clear_args
run_gx --new "inline brief here" >/dev/null 2>&1
grep -q "gx:adhoc" "$OUT/opencode.args" && ok "A3 adhoc title" || bad "A3 adhoc title"
has    "A3 inline message"      "inline brief here"
absent "A3 no -f inline"        "-f"

echo "----"
[[ "$FAIL" == 0 ]] && { echo "ALL PASS"; exit 0; } || { echo "SOME FAILED"; exit 1; }
