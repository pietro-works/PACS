#!/usr/bin/env bash
# Hook tests: marker logic of the three read-enforcement hooks.
# Needs jq. Set PACS_HOOKS_DIR to test another copy of the scripts.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS="${PACS_HOOKS_DIR:-$TEST_DIR/../pacs-hooks/hooks}"
PASSED=0
FAILED=0

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not found, hook tests need it"
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pacs-hooktest.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
REAL="$(cd "$WORK" && pwd -P)"

# Layout: $REAL/proj (registry), $REAL/other, $REAL/link -> $REAL (symlinked prefix)
mkdir -p "$REAL/proj/sub" "$REAL/other"
printf '# registry\n' >"$REAL/proj/AGENTS.md"
printf '# other\n' >"$REAL/other/AGENTS.md"
ln -s "$REAL" "$REAL/link"
PROJ="$REAL/proj"
MARKER="$PROJ/.claude/.pacs-registry-read"

# A PATH with the tools the hooks need but NO realpath (macOS 12 and older).
NOREAL="$REAL/bin-norealpath"
mkdir -p "$NOREAL"
for t in jq dirname basename mkdir date cat rm; do
  p="$(command -v "$t" 2>/dev/null)" && ln -s "$p" "$NOREAL/$t"
done

pass() { echo "  ✓ [PASS] $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ [FAIL] $1"; FAILED=$((FAILED + 1)); }

# mark_case NAME EXPECT(yes|no) FILE_PATH [EXTRA_JSON] [PATH_OVERRIDE]
mark_case() {
  local name="$1" expect="$2" fp="$3" extra="${4:-}" pth="${5:-$PATH}" payload got
  [ -n "$extra" ] || extra='{}'
  rm -rf "$PROJ/.claude"
  payload="$(jq -nc --arg cwd "$PROJ" --arg fp "$fp" --argjson ex "$extra" '{cwd:$cwd,tool_input:({file_path:$fp} + $ex)}')"
  (cd "$PROJ" && printf '%s' "$payload" | env PATH="$pth" /bin/bash "$HOOKS/pacs-mark-read.sh") >/dev/null 2>&1
  if [ -f "$MARKER" ]; then got=yes; else got=no; fi
  if [ "$got" = "$expect" ]; then pass "$name"; else fail "$name (marker: $got, wanted: $expect)"; fi
}

# gate_case NAME WANT_EXIT
gate_case() {
  local name="$1" want="$2" rc
  printf '{"cwd":"%s"}' "$PROJ" | (cd "$PROJ" && /bin/bash "$HOOKS/pacs-enforce-read.sh") >/dev/null 2>&1
  rc=$?
  if [ "$rc" = "$want" ]; then pass "$name"; else fail "$name (exit $rc, wanted $want)"; fi
}

echo "=== Hook tests: mark-read (path matching) ==="
mark_case "Exact absolute path marks"                         yes "$PROJ/AGENTS.md"
mark_case "Path through a symlinked prefix marks"             yes "$REAL/link/proj/AGENTS.md"
mark_case "Double slash marks"                                yes "$PROJ//AGENTS.md"
mark_case "Dot-dot through an existing dir marks"             yes "$PROJ/sub/../AGENTS.md"
mark_case "Another project's AGENTS.md does not mark"         no  "$REAL/other/AGENTS.md"
mark_case "A nested sub/AGENTS.md does not mark"              no  "$PROJ/sub/AGENTS.md"
mark_case "AGENTS.md.bak does not mark"                       no  "$PROJ/AGENTS.md.bak"
mark_case "Empty file_path does not mark"                     no  ""
mark_case "Partial read (limit) does not mark"                no  "$PROJ/AGENTS.md" '{"limit":3}'
mark_case "Partial read (offset) does not mark"               no  "$PROJ/AGENTS.md" '{"offset":0}'

echo "=== Hook tests: mark-read with no realpath on PATH ==="
mark_case "Exact path marks (no realpath)"                    yes "$PROJ/AGENTS.md" '' "$NOREAL"
mark_case "Symlinked prefix marks (no realpath)"              yes "$REAL/link/proj/AGENTS.md" '' "$NOREAL"
mark_case "Double slash marks (no realpath)"                  yes "$PROJ//AGENTS.md" '' "$NOREAL"
mark_case "Another project's AGENTS.md does not mark (no realpath)" no "$REAL/other/AGENTS.md" '' "$NOREAL"

echo "=== Hook tests: hostile inputs ==="
# A path longer than PATH_MAX makes dirname fail; the matcher must not guess a directory.
SEG="$(printf 'd%.0s' $(seq 1 200))"
LONG="$SEG/$SEG/$SEG/$SEG/$SEG/$SEG"
mark_case "Over-long nonexistent path ending in AGENTS.md does not mark"              no "$PROJ/$LONG/AGENTS.md"
mark_case "Over-long nonexistent path does not mark (no realpath)"                    no "$PROJ/$LONG/AGENTS.md" '' "$NOREAL"
# A file really named "AGENTS.md<newline>" must not be mistaken for the registry.
if : >"$PROJ/AGENTS.md"$'\n' 2>/dev/null; then
  mark_case "A file named AGENTS.md<newline> does not mark"                           no "$PROJ/AGENTS.md"$'\n'
fi
# CDPATH must not redirect the directory lookup of a relative path.
mkdir -p "$REAL/cdp/proj"
rm -rf "$PROJ/.claude"
payload="$(jq -nc --arg cwd "$PROJ" --arg fp "proj/AGENTS.md" '{cwd:$cwd,tool_input:{file_path:$fp}}')"
(cd "$REAL" && printf '%s' "$payload" | env PATH="$NOREAL" CDPATH="$REAL/cdp" /bin/bash "$HOOKS/pacs-mark-read.sh") >/dev/null 2>&1
if [ -f "$MARKER" ]; then pass "Relative path with CDPATH exported marks the right file (no realpath)"; else fail "Relative path with CDPATH exported (marker missing)"; fi

echo "=== Hook tests: enforce and reset ==="
# A populated registry so the gate has something to enforce.
# shellcheck disable=SC2016
printf '# registry\n\n## PACS Registry\n\n```yaml\nPACS0001:\n  anchor: "x:Y"\n```\n' >"$PROJ/AGENTS.md"
rm -rf "$PROJ/.claude"
gate_case "Edit is blocked before the registry is read (exit 2)" 2
printf '{"cwd":"%s","tool_input":{"file_path":"%s"}}' "$PROJ" "$PROJ/AGENTS.md" | (cd "$PROJ" && /bin/bash "$HOOKS/pacs-mark-read.sh") >/dev/null 2>&1
gate_case "Edit is allowed after a full read (exit 0)" 0
printf '{"cwd":"%s"}' "$PROJ" | (cd "$PROJ" && /bin/bash "$HOOKS/pacs-reset-marker.sh") >/dev/null 2>&1
gate_case "Edit is blocked again after SessionStart resets the marker (exit 2)" 2
printf '# registry\n\n## PACS Registry\n\n```yaml\n# nothing minted yet\n```\n' >"$PROJ/AGENTS.md"
gate_case "An empty registry fails open (exit 0)" 0

echo
echo "=== Hook test summary ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
[ "$FAILED" -eq 0 ] || exit 1
