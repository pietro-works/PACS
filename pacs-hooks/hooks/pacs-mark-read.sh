#!/bin/bash
# Resolve the project from the hook payload's cwd, falling back to this
# script's own location — see pacs-enforce-read.sh for why. Both scripts must
# resolve the SAME project root or the marker written here never satisfies the
# gate there, so keep this block identical in both.
HOOK_INPUT=$(cat)
PROJECT_DIR=$(printf '%s' "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[[ -n "$PROJECT_DIR" && -f "${PROJECT_DIR}/AGENTS.md" ]] \
  || PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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
