#!/usr/bin/env bash
# Hook tests for pacs-gate.sh and its three wrappers.
# Needs jq. Set PACS_HOOKS_DIR to test another copy of the scripts.
# The registry fixtures hold backticks on purpose, so single quotes are right.
# shellcheck disable=SC2016
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
R="$(cd "$WORK" && pwd -P)"
export PACS_STATE_DIR="$R/state"

ENTRY='# registry\n\n## PACS Registry\n\n```yaml\nPACS0001:\n  anchor: "x:Y"\n```\n'
NONE='# registry\n\n## PACS Registry\n\n```yaml\n# nothing minted yet\n```\n'
mk() { mkdir -p "$(dirname "$1")"; printf "$2" >"$1"; }

# Layout
mk "$R/p/AGENTS.md" "$ENTRY"; mkdir -p "$R/p/.git" "$R/p/sub"; : >"$R/p/sub/a.js"
mk "$R/p/pkg/AGENTS.md" "$NONE"
mk "$R/p/vendor/lib/AGENTS.md" "$NONE"; mkdir -p "$R/p/vendor/lib/.git"
mk "$R/q/AGENTS.md" "$ENTRY"; mkdir -p "$R/q/.git"
mk "$R/wt/AGENTS.md" "$ENTRY"; : >"$R/wt/.git"
mk "$R/empty/AGENTS.md" "$NONE"; mkdir -p "$R/empty/.git"
mk "$R/table/AGENTS.md" '# docs\n\n| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n'; mkdir -p "$R/table/.git"
mkdir -p "$R/outside"
ln -s "$R/p" "$R/plink"

pass() { echo "  ✓ [PASS] $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ [FAIL] $1"; FAILED=$((FAILED + 1)); }

# run SCRIPT SESSION CWD FILE [EXTRA-JSON] -> exit code; EXTRA is merged into the payload
run() {
  local sc="$1" sid="$2" cwd="$3" fp="$4" ex="${5:-}" payload
  [ -n "$ex" ] || ex='{}'
  payload=$(jq -nc --arg s "$sid" --arg c "$cwd" --arg f "$fp" --argjson ex "$ex" \
    '{session_id:$s, cwd:$c} + (if $f == "" then {} else {tool_input:{file_path:$f}} end) * $ex')
  (cd "$R" && printf '%s' "$payload" | /bin/bash "$HOOKS/$sc" >/dev/null 2>&1)
  echo $?
}
reset() { run pacs-reset-marker.sh "${1:-s1}" "$R/p" "" >/dev/null; }
mark() { run pacs-mark-read.sh "${3:-s1}" "$R/p" "$1" "${2:-}" >/dev/null; }
edit() { run pacs-enforce-read.sh "${3:-s1}" "${2:-$R/p}" "$1"; }
expect() { if [ "$3" = "$2" ]; then pass "$1"; else fail "$1 (exit $3, wanted $2)"; fi; }

echo "=== Gate: which registry governs a file ==="
reset; expect "Edit in a project before its registry is read is blocked"           2 "$(edit "$R/p/sub/a.js")"
reset; mark "$R/p/AGENTS.md"
       expect "Edit is allowed after a full read"                                 0 "$(edit "$R/p/sub/a.js")"
reset; expect "A new file in a folder that does not exist yet is still governed"   2 "$(edit "$R/p/new/dir/b.js")"
reset; expect "A nested package with an empty registry uses the root registry"     2 "$(edit "$R/p/pkg/c.js")"
reset; expect "A nested git repo with an empty registry is not gated"              0 "$(edit "$R/p/vendor/lib/d.js")"
reset; expect "A file outside every project is not gated, whatever the cwd"        0 "$(edit "$R/outside/e.js" "$R/p")"
reset; expect "cwd outside, file inside a project: still blocked"                  2 "$(edit "$R/p/sub/a.js" "$R/outside")"
reset; mark "$R/p/AGENTS.md"
       expect "cwd in a worktree with its own registry, edit in the main project"  0 "$(edit "$R/p/sub/a.js" "$R/wt")"
reset; mark "$R/p/AGENTS.md"
       expect "Reading one project's registry does not unlock another"            2 "$(edit "$R/q/f.js")"
reset; mark "$R/p/AGENTS.md"
       expect "Read by real path, edit through a symlink: allowed"                 0 "$(edit "$R/plink/sub/a.js")"
reset; mark "$R/plink/AGENTS.md"
       expect "Read through a symlink, edit by real path: allowed"                 0 "$(edit "$R/p/sub/a.js")"
reset; expect "An empty registry is not gated"                                     0 "$(edit "$R/empty/g.js")"
reset; expect "A Markdown table without PACS entries is not a registry"            0 "$(edit "$R/table/h.js")"
reset; expect "A relative path resolves against the payload cwd"                   2 "$(edit "sub/a.js")"

echo "=== Gate: what counts as a full read ==="
reset; mark "$R/p/AGENTS.md" '{"tool_input":{"limit":3}}'
       expect "A read with limit and no response does not count"                   2 "$(edit "$R/p/sub/a.js")"
reset; mark "$R/p/AGENTS.md" '{"tool_input":{"offset":0}}'
       expect "A read with offset and no response does not count"                  2 "$(edit "$R/p/sub/a.js")"
reset; mark "$R/p/AGENTS.md" '{"tool_response":{"file":{"startLine":1,"numLines":5,"totalLines":9}}}'
       expect "A response with fewer lines than the file does not count"           2 "$(edit "$R/p/sub/a.js")"
reset; mark "$R/p/AGENTS.md" '{"tool_response":{"file":{"startLine":1,"numLines":9,"totalLines":9,"truncatedByTokenCap":true}}}'
       expect "A read cut by the token cap does not count"                        2 "$(edit "$R/p/sub/a.js")"
reset; mark "$R/p/AGENTS.md" '{"tool_input":{"limit":5000},"tool_response":{"file":{"startLine":1,"numLines":9,"totalLines":9}}}'
       expect "A limit that still covers the whole file counts"                   0 "$(edit "$R/p/sub/a.js")"
reset; mark "$R/p/pkg/AGENTS.md"
       expect "Reading a nested empty registry does not unlock the root"           2 "$(edit "$R/p/sub/a.js")"
reset; mark "$R/p/AGENTS.md.bak"
       expect "AGENTS.md.bak does not count"                                       2 "$(edit "$R/p/sub/a.js")"
reset; mark "$R/p/sub/../AGENTS.md"
       expect "A path with .. counts"                                              0 "$(edit "$R/p/sub/a.js")"
if : >"$R/p/AGENTS.md"$'\n' 2>/dev/null; then
  reset; mark "$R/p/AGENTS.md"$'\n'
         expect "A file named AGENTS.md<newline> does not count"                   2 "$(edit "$R/p/sub/a.js")"
fi

echo "=== Gate: sessions ==="
reset s1; reset s2; mark "$R/p/AGENTS.md" "" s1
expect "One session's read does not unlock another session"                        2 "$(edit "$R/p/sub/a.js" "$R/p" s2)"
expect "The reading session is unlocked"                                           0 "$(edit "$R/p/sub/a.js" "$R/p" s1)"
reset s2
expect "Another session's start does not clear this one"                           0 "$(edit "$R/p/sub/a.js" "$R/p" s1)"
reset s1
expect "This session's start (or compaction) clears its reads"                     2 "$(edit "$R/p/sub/a.js" "$R/p" s1)"
reset; mark "$R/p/AGENTS.md"
expect "A subagent (same session id) shares the session's reads"                   0 "$(run pacs-enforce-read.sh s1 "$R/p" "$R/p/sub/a.js" '{"agent_id":"a1"}')"
expect "An odd session id cannot escape the state folder" 2 "$(edit "$R/p/sub/a.js" "$R/p" '../../x')"
[ ! -e "$R/x" ] && [ -z "$(find "$R/state" -type f ! -name 'read-*')" ] && pass "State files stay inside the state folder" || fail "State file written outside the state folder"

echo "=== Gate: failing open ==="
expect "No file_path: allowed"                                                     0 "$(edit "")"
r=$(cd "$R" && printf 'not json' | /bin/bash "$HOOKS/pacs-enforce-read.sh" >/dev/null 2>&1; echo $?)
expect "Input that is not JSON: allowed"                                           0 "$r"
NOJQ="$R/nojq"; mkdir -p "$NOJQ"
for t in bash cat grep tr dirname mkdir rm; do p="$(command -v "$t" 2>/dev/null)" && ln -s "$p" "$NOJQ/$t"; done
r=$(cd "$R" && printf '{"session_id":"s9","tool_input":{"file_path":"%s"}}' "$R/p/sub/a.js" | env PATH="$NOJQ" /bin/bash "$HOOKS/pacs-enforce-read.sh" >/dev/null 2>&1; echo $?)
expect "No jq on PATH: allowed"                                                    0 "$r"
r=$( (cd "$R" && printf '{"session_id":"s1","tool_input":{"file_path":"%s"}}' "$R/p/sub/a.js" | /bin/bash "$HOOKS/pacs-gate.sh" >/dev/null 2>&1; echo $?) )
expect "No mode and no hook_event_name: does nothing"                             0 "$r"
reset
r=$( (cd "$R" && printf '{"session_id":"s1","hook_event_name":"PreToolUse","tool_input":{"file_path":"%s"}}' "$R/p/sub/a.js" | /bin/bash "$HOOKS/pacs-gate.sh" >/dev/null 2>&1; echo $?) )
expect "Mode taken from hook_event_name when no argument is given"                 2 "$r"
msg=$(cd "$R" && printf '{"session_id":"s3","tool_input":{"file_path":"%s"}}' "$R/p/sub/a.js" | /bin/bash "$HOOKS/pacs-enforce-read.sh" 2>&1 >/dev/null)
case "$msg" in *"$R/p/AGENTS.md"*) pass "The block message names the registry to read" ;; *) fail "Block message: $msg" ;; esac

echo
echo "=== Hook test summary ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
[ "$FAILED" -eq 0 ] || exit 1
