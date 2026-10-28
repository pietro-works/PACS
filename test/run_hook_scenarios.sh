#!/usr/bin/env bash
# test/run_hook_scenarios.sh — which project do the hooks gate when cwd moves?
#
# Claude Code's payload `cwd` follows a Bash `cd`, so the three hooks can be
# called from different folders inside one session. These scenarios check that
# they still agree on the project, the registry and the marker.
# Needs jq. Set PACS_HOOKS_DIR to test another copy of the scripts.
# The registry fixtures hold backticks on purpose, so single quotes are right,
# and mk() takes its printf format from the fixture text on purpose.
# shellcheck disable=SC2016,SC2059
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS="${PACS_HOOKS_DIR:-$TEST_DIR/../pacs-hooks/hooks}"
PASSED=0
FAILED=0

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not found, hook tests need it"
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pacs-scenarios.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
REAL="$(cd "$WORK" && pwd -P)"

pass() { echo "  ✓ [PASS] $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ [FAIL] $1"; FAILED=$((FAILED + 1)); }
expect() { # NAME WANT GOT  (exit codes: 2 = edit blocked, 0 = edit allowed)
  if [ "$3" = "$2" ]; then pass "$1"; else fail "$1 (exit $3, wanted $2)"; fi
}

ENTRY='## PACS Registry\n\n```yaml\nPACS0001:\n  anchor: "x:Y"\n```\n'
NONE='## PACS Registry\n\n```yaml\n# none\n```\n'
mk() { mkdir -p "$(dirname "$1")"; printf "# registry\n\n$2" >"$1"; }

# hk SCRIPTS-DIR EVENT CWD [FILE] [EXTRA-JSON] -> prints the hook's exit code
hk() {
  local s="$1" ev="$2" cwd="$3" fp="${4:-}" ex="${5:-}" sc payload
  case "$ev" in reset) sc=pacs-reset-marker.sh ;; mark) sc=pacs-mark-read.sh ;; enf) sc=pacs-enforce-read.sh ;; esac
  [ -n "$ex" ] || ex='{}'
  payload="$(jq -nc --arg cwd "$cwd" --arg fp "$fp" --argjson ex "$ex" \
    '(if $cwd=="" then {} else {cwd:$cwd} end) + (if $fp=="" then {} else {tool_input:({file_path:$fp}+$ex)} end)')"
  (cd "${cwd:-$REAL}" 2>/dev/null || cd "$REAL" || exit; printf '%s' "$payload" | /bin/bash "$s/$sc" >/dev/null 2>&1)
  echo $?
}

# scenarios LABEL empty|populated  — builds a fresh layout and runs everything
scenarios() {
  local greg="$2" L="$REAL/$1" G PPH P
  mkdir -p "$L/g/pacs-hooks/hooks" "$L/pp/.claude/hooks"
  cp -p "$HOOKS"/*.sh "$L/g/pacs-hooks/hooks/"
  cp -p "$HOOKS"/*.sh "$L/pp/.claude/hooks/"
  G="$L/g/pacs-hooks/hooks"; PPH="$L/pp/.claude/hooks"
  # global layout: scripts run in place, so ../.. is the PACS repo itself
  if [ "$greg" = populated ]; then mk "$L/g/AGENTS.md" "$ENTRY"; else mk "$L/g/AGENTS.md" "$NONE"; fi
  mk "$L/pp/AGENTS.md" "$ENTRY"; mk "$L/pp/other/AGENTS.md" "$ENTRY"
  mkdir -p "$L/proj/.git" "$L/proj/sub" "$L/elsewhere" "$L/proj/vendor/lib/.git"
  mk "$L/proj/AGENTS.md" "$ENTRY"
  mk "$L/proj/pkg/AGENTS.md" "$NONE"
  mk "$L/proj/vendor/lib/AGENTS.md" "$NONE"
  mk "$L/empty/AGENTS.md" "$NONE"
  ln -s "$L/proj" "$L/projlink"
  # scripts installed under <dir>/.claude/hooks where <dir> has no AGENTS.md (a user-level install)
  mkdir -p "$L/home/.claude/hooks"; cp -p "$HOOKS"/*.sh "$L/home/.claude/hooks/"
  # a project whose hooks folder is a symlink to a template project's hooks
  mkdir -p "$L/tmpl/.claude/hooks" "$L/p2/.claude"; cp -p "$HOOKS"/*.sh "$L/tmpl/.claude/hooks/"
  mk "$L/tmpl/AGENTS.md" "$ENTRY"; mk "$L/p2/AGENTS.md" "$ENTRY"
  ln -s "$L/tmpl/.claude/hooks" "$L/p2/.claude/hooks"
  P="$L/proj"
  clean() { for d in proj proj/pkg proj/vendor/lib empty g pp pp/other elsewhere tmpl p2; do rm -f "$L/$d/.claude/.pacs-registry-read"; done; }

  echo "=== Hook scenarios [PACS repo registry: $greg] ==="
  clean; expect "Edit at the project root before any read is blocked"                  2 "$(hk "$G" enf "$P")"
  clean; hk "$G" mark "$P" "$P/AGENTS.md" >/dev/null
         expect "Edit at the project root after a full read is allowed"                 0 "$(hk "$G" enf "$P")"
  clean; expect "Drifted into a subfolder: edit before any read is blocked"            2 "$(hk "$G" enf "$P/sub")"
  clean; hk "$G" mark "$P/sub" "$P/AGENTS.md" >/dev/null
         expect "Read from a subfolder, edit in the subfolder: allowed"                 0 "$(hk "$G" enf "$P/sub")"
  clean; hk "$G" mark "$P" "$P/AGENTS.md" >/dev/null
         expect "Read at the root, then drift: edit allowed"                            0 "$(hk "$G" enf "$P/sub")"
  clean; hk "$G" mark "$P/sub" "$P/AGENTS.md" >/dev/null
         expect "Read from a subfolder, edit back at the root: allowed"                 0 "$(hk "$G" enf "$P")"
  clean; hk "$G" mark "$P" "$P/AGENTS.md" >/dev/null; hk "$G" reset "$P/sub" >/dev/null
         expect "Compaction while drifted clears the marker for the whole project"      2 "$(hk "$G" enf "$P")"
  clean; hk "$G" mark "$P" "$P/AGENTS.md" >/dev/null; hk "$G" reset "$P" >/dev/null
         expect "Compaction at the root, then drift: edit blocked again"                2 "$(hk "$G" enf "$P/sub")"
  clean; expect "Nested package with no registry uses the root registry: blocked"      2 "$(hk "$G" enf "$P/pkg")"
  clean; hk "$G" mark "$P" "$P/AGENTS.md" >/dev/null
         expect "Nested package: allowed after the root registry was read"              0 "$(hk "$G" enf "$P/pkg")"
  clean; expect "A session outside any PACS project is never gated"                    0 "$(hk "$G" enf "$L/elsewhere")"
  clean; expect "A project whose registry is empty is not gated"                       0 "$(hk "$G" enf "$L/empty")"
  clean; expect "A payload without cwd gates nothing"                                  0 "$(hk "$G" enf '')"
  clean; expect "A nested git repo with an empty registry is its own project"          0 "$(hk "$G" enf "$P/vendor/lib")"
  clean; hk "$G" mark "$P" "$P/AGENTS.md" >/dev/null
         expect "Read by real path, edit through a symlinked cwd: allowed"              0 "$(hk "$G" enf "$L/projlink")"
  clean; hk "$G" mark "$P/sub" "$P/AGENTS.md" '{"limit":3}' >/dev/null
         expect "A partial read from a subfolder does not clear the gate"               2 "$(hk "$G" enf "$P/sub")"
  clean; hk "$G" reset "$P/sub" >/dev/null; hk "$G" mark "$P/sub" "$P/AGENTS.md" >/dev/null
         expect "Session started in a subfolder: read, then edit"                       0 "$(hk "$G" enf "$P/sub")"
  clean; expect "Per-project install drifted into another project: still blocked"      2 "$(hk "$PPH" enf "$L/pp/other")"
  clean; hk "$PPH" mark "$L/pp/other" "$L/pp/AGENTS.md" >/dev/null
         expect "Per-project install: reading its own registry from a drifted cwd"      0 "$(hk "$PPH" enf "$L/pp/other")"
  clean; expect "Scripts in ~/.claude/hooks (no AGENTS.md beside them) still gate the cwd project" 2 "$(hk "$L/home/.claude/hooks" enf "$P")"
  clean; hk "$L/home/.claude/hooks" mark "$P" "$P/AGENTS.md" >/dev/null
         expect "Same install: allowed once that project's registry was read"           0 "$(hk "$L/home/.claude/hooks" enf "$P")"
  clean; expect "Symlinked hooks folder: the linking project's own registry is required" 2 "$(hk "$L/p2/.claude/hooks" enf "$L/p2")"
  clean; hk "$L/p2/.claude/hooks" mark "$L/p2" "$L/tmpl/AGENTS.md" >/dev/null
         expect "Symlinked hooks folder: reading the template project's registry does not unlock" 2 "$(hk "$L/p2/.claude/hooks" enf "$L/p2")"
  clean; hk "$L/p2/.claude/hooks" mark "$L/p2" "$L/p2/AGENTS.md" >/dev/null
         expect "Symlinked hooks folder: reading its own registry unlocks"              0 "$(hk "$L/p2/.claude/hooks" enf "$L/p2")"
}

scenarios empty empty
scenarios populated populated

echo "=== Hook scenarios: guards ==="
G="$REAL/empty/g/pacs-hooks/hooks"
hang="ok"
(cd "$REAL" && printf '{"cwd":"."}' | /bin/bash "$G/pacs-enforce-read.sh" >/dev/null 2>&1 & pid=$!
  i=0; while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid"; echo hang; fi) >"$REAL/hang.out" 2>/dev/null
[ -s "$REAL/hang.out" ] && hang="hang"
if [ "$hang" = ok ]; then pass "A relative cwd returns at once instead of looping"; else fail "A relative cwd makes the climb loop"; fi

sums=""
for f in pacs-enforce-read pacs-mark-read pacs-reset-marker; do
  s="$(sed -n '/^# >>> project-root resolution/,/^# <<< project-root resolution/p' "$HOOKS/$f.sh" | cksum)"
  sums="$sums|$s"
done
distinct="$(printf '%s' "${sums#|}" | tr '|' '\n' | sort -u | wc -l | tr -d ' ')"
if [ "$distinct" = 1 ] && [ -n "$(sed -n '/^# >>> project-root resolution/,/^# <<< project-root resolution/p' "$HOOKS/pacs-mark-read.sh")" ]; then
  pass "The project-root block is identical in all three scripts"
else
  fail "The project-root block differs between the scripts, or is missing"
fi

echo
echo "=== Hook scenario summary ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
[ "$FAILED" -eq 0 ] || exit 1
