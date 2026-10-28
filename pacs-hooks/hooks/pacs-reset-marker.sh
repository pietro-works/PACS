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
# PACS enforcement — SessionStart hook
#
# Fires on every session start: a fresh session, /clear, /resume, a forked
# session, AND a session start caused by auto/manual compaction. Deletes the
# "AGENTS.md was read" marker so the PreToolUse hook (pacs-enforce-read.sh)
# can't be satisfied by a read that happened before the context was wiped.
#
# This is the piece that actually closes the compaction gap: it doesn't try
# to detect "was this summarized," it just clears the marker unconditionally
# on every SessionStart, so the only way to set it again is a real Read tool
# call on AGENTS.md, every time.

MARKER="${PROJECT_DIR}/.claude/.pacs-registry-read"
rm -f "$MARKER"
exit 0
