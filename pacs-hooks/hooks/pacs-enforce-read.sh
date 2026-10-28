#!/bin/bash
# >>> project-root resolution (keep identical in all three hook scripts)
#
# Where the scripts live decides what "the project" means:
#   - installed per project, under <project>/.claude/hooks/ next to that project's
#     AGENTS.md: that project, always.
#   - installed once and run in place (global): the nearest AGENTS.md at or above
#     the payload's cwd that has registry entries, so a session that has cd'd into
#     a subfolder still finds the same registry and the same marker. The climb
#     stops after the first directory holding a .git, so it never leaves the repo.
#     If no registry on the way up has entries, the nearest AGENTS.md is used.
# If neither finds a project the hook does nothing. It never falls back to the
# folder the scripts live in: for a global install that folder is the PACS repo,
# and gating every other project on its registry would block them all.
pacs_has_entries() {
  local n p
  n=$(grep -cE '^[[:space:]]*PACS[0-9]{4}:' "$1" 2>/dev/null)
  p=$(grep -cE '^[[:space:]]*\|' "$1" 2>/dev/null)
  [ "${n:-0}" -gt 0 ] || [ "${p:-0}" -gt 2 ]
}
pacs_find_root() {
  local d="$1" first="" up
  case "$d" in /*) ;; *) return 0 ;; esac
  [ -d "$d" ] || return 0
  while :; do
    if [ -f "$d/AGENTS.md" ]; then
      [ -n "$first" ] || first="$d"
      if pacs_has_entries "$d/AGENTS.md"; then printf '%s' "$d"; return 0; fi
    fi
    [ -e "$d/.git" ] && break
    up=$(dirname "$d" 2>/dev/null)
    { [ -n "$up" ] && [ "$up" != "$d" ]; } || break
    d="$up"
  done
  [ -z "$first" ] || printf '%s' "$first"
  return 0
}
HOOK_INPUT=$(cat)
SELF_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
PROJECT_DIR=""
case "$SELF_DIR" in
  */.claude/hooks) [ -f "${SELF_DIR%/.claude/hooks}/AGENTS.md" ] && PROJECT_DIR="${SELF_DIR%/.claude/hooks}" ;;
esac
[ -n "$PROJECT_DIR" ] || PROJECT_DIR=$(pacs_find_root "$(printf '%s' "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null)")
[ -n "$PROJECT_DIR" ] || exit 0
# <<< project-root resolution
# PACS enforcement — PreToolUse hook, matched to Edit|Write|MultiEdit
#
# Blocks an edit until the marker from pacs-mark-read.sh exists, i.e. until
# THIS project's registry (${PROJECT_DIR}/AGENTS.md) has actually been
# Read since the last SessionStart (which includes post-compaction restarts,
# since pacs-reset-marker.sh clears the marker there too).
#
# Fails OPEN when there is nothing to consult: if the registry file doesn't
# exist yet, or its PACS Registry table has zero data rows (header + separator
# only), the block is pointless — it would just force a ritual read of an
# empty file, which is what deadlocks a fresh repo and adds friction after
# every compaction. In that case the edit is allowed.
#
# Exit 2 is a blocking error for PreToolUse: Claude Code stops the tool call
# and feeds the stderr text back to Claude as the reason.

REGISTRY="${PROJECT_DIR%/}/AGENTS.md"
MARKER="${PROJECT_DIR}/.claude/.pacs-registry-read"

# No registry file yet — nothing to read, don't block (bootstrap it per SPEC).
[[ -f "$REGISTRY" ]] || exit 0

# Count registry entries. The current format is a YAML block under
# "## PACS Registry", where an entry is a top-level `PACS####:` key; the
# commented-out example lines start with '#' and don't match. Legacy v1
# registries are markdown tables, where a well-formed empty table still has
# two lines starting with '|' (header + separator). Zero entries either way
# means nothing to consult, so allow the edit.
#
# Note: `grep -c` prints 0 and exits 1 on no match, so a `|| echo 0` fallback
# would emit "0\n0" and blow up the arithmetic test below — which fails CLOSED
# and blocks every edit. Take the output as-is and default only if it's empty.
entries=$(grep -cE '^[[:space:]]*PACS[0-9]{4}:' "$REGISTRY" 2>/dev/null)
pipe_lines=$(grep -cE '^[[:space:]]*\|' "$REGISTRY" 2>/dev/null)
entries=${entries:-0}
pipe_lines=${pipe_lines:-0}
[[ "$entries" -eq 0 && "$pipe_lines" -le 2 ]] && exit 0

# Populated registry: require that it was actually read this session.
if [[ ! -f "$MARKER" ]]; then
  echo "Read this project's AGENTS.md in full before editing code (the PACS Registry lives there — see SPEC.md section 0). Use the Read tool on ${REGISTRY}, with no limit or offset, then retry this edit." >&2
  exit 2
fi

exit 0
