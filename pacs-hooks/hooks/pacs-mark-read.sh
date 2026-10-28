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
# PACS enforcement — PostToolUse hook, matched to the Read tool
#
# Sets the "registry was read" marker, but ONLY when the file just read is
# THIS project's registry — exactly ${PROJECT_DIR}/AGENTS.md, not any
# path that merely ends in "AGENTS.md". Without this exact match, reading an
# unrelated AGENTS.md (a global ~/.claude/AGENTS.md, or another repo's) would
# satisfy the gate without the project's registry ever being opened.
#
# Requires jq to parse the tool-call JSON. If your registry lives elsewhere
# (ARCHITECTURE.md, docs/PACS.md, ...), change REGISTRY below to match.

INPUT="$HOOK_INPUT"
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -n "$FILE_PATH" ]] || exit 0
# A newline in a path is never the registry. Check it in jq, because the $(...)
# above already stripped any trailing newline, which would make a file named
# "AGENTS.md<newline>" look like "AGENTS.md".
if printf '%s' "$INPUT" | jq -e '(.tool_input.file_path // "") | contains("\n")' >/dev/null 2>&1; then
  exit 0
fi

REGISTRY="${PROJECT_DIR%/}/AGENTS.md"

# Normalize both sides so trailing slashes / symlinks / "//" / ".." don't cause
# a miss. GNU `realpath -m` is not everywhere: macOS ships a BSD realpath with
# no -m, and macOS 12 and older ship no realpath at all. Try the GNU form, then
# plain realpath (BSD, existing paths), then resolve the directory physically.
# Both sides go through the same function, so they always compare alike.
#
# Safety rule: when anything is doubtful, return the path unchanged. An
# unchanged path can only miss (the gate stays closed, nothing is let through
# by mistake); a guessed directory could make two different files look equal.
norm_path() {
  local p="${1-}" r d b
  case "$p" in "") return 0 ;; -*) p="./$p" ;; esac
  if r=$(realpath -m "$p" 2>/dev/null); then printf '%s' "$r"; return 0; fi
  if r=$(realpath "$p" 2>/dev/null); then printf '%s' "$r"; return 0; fi
  d=$(dirname "$p" 2>/dev/null); b=$(basename "$p" 2>/dev/null)
  if [ -n "$d" ] && [ -n "$b" ] && d=$(CDPATH='' cd "$d" 2>/dev/null && pwd -P) && [ -n "$d" ]; then
    printf '%s/%s' "${d%/}" "$b"; return 0
  fi
  printf '%s' "$p"
}
fp=$(norm_path "$FILE_PATH")
rg=$(norm_path "$REGISTRY")

if [[ "$fp" == "$rg" ]]; then
  # Reject partial reads. A Read that used limit/offset only skimmed the
  # registry (e.g. `Read AGENTS.md limit 3`) — a token gesture to clear the
  # gate, not an actual consultation. Only a full read of the file counts.
  LIMIT=$(echo "$INPUT" | jq -r '.tool_input.limit // empty')
  OFFSET=$(echo "$INPUT" | jq -r '.tool_input.offset // empty')
  if [[ -n "$LIMIT" || -n "$OFFSET" ]]; then
    exit 0
  fi
  MARKER="${PROJECT_DIR}/.claude/.pacs-registry-read"
  mkdir -p "$(dirname "$MARKER")"
  date +%s > "$MARKER"
fi

exit 0
