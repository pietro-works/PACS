#!/bin/bash
# PACS read gate — one script for the three Claude Code hook events.
#
#   reset    SessionStart                     forget what this session has read
#   mark     PostToolUse on Read              remember a registry read in full
#   enforce  PreToolUse on Edit|Write|...     exit 2 until the edited file's registry was read
#
# The registry that governs a file is the nearest AGENTS.md with PACS entries at
# or above it, stopping at the first folder holding .git. Reads are remembered
# per session id, outside every project. A subagent shares its parent's session
# id, and a subagent's compaction resets the whole session.
#
# Only a positive "registry exists and is unread" blocks. Missing jq, bad input
# or no governing registry lets the call through.
#
# Usage: pacs-gate.sh [reset|mark|enforce]   (default: from hook_event_name)

command -v jq >/dev/null 2>&1 || exit 0
IN=$(cat)

EVENT="" SID="" FP="" CWD="" FULL=""
eval "$(printf '%s' "$IN" | jq -r '
  (.tool_response.file // null) as $f
  | (.tool_input.limit // .tool_input.offset) as $part
  | @sh "EVENT=\(.hook_event_name // "") SID=\(.session_id // "") FP=\(.tool_input.file_path // "") CWD=\(.cwd // "") FULL=\(
      if $f == null then (if $part == null then "yes" else "no" end)
      elif $f.truncatedByTokenCap == true then "no"
      elif ($f.startLine // 1) == 1 and ($f.numLines // -1) >= ($f.totalLines // 0) then "yes"
      else "no" end)"' 2>/dev/null)"

MODE="${1:-}"
case "$MODE:$EVENT" in
  :SessionStart) MODE=reset ;;
  :PostToolUse) MODE=mark ;;
  :PreToolUse) MODE=enforce ;;
esac

SID=$(printf '%s' "$SID" | tr -cd 'A-Za-z0-9_-')
STATE="${PACS_STATE_DIR:-$HOME/.cache/pacs}/read-${SID:-nosession}"

case "$FP" in
  *$'\n'*) exit 0 ;;
  /* | "") ;;
  *) [ -n "$CWD" ] && FP="$CWD/$FP" ;;
esac

# Physical path of the folder holding the registry that governs path $1, or nothing.
governing_root() {
  local d="$1"
  while [ ! -d "$d" ]; do
    case "$d" in */*) d="${d%/*}"; d="${d:-/}" ;; *) d=. ;; esac
  done
  d=$(CDPATH='' cd -P "$d" 2>/dev/null && pwd -P) || return 0
  while :; do
    if [ -f "$d/AGENTS.md" ] && grep -qE '^[[:space:]]*PACS[0-9]{4}:' "$d/AGENTS.md" 2>/dev/null; then
      printf '%s' "$d"
      return 0
    fi
    [ -e "$d/.git" ] || [ "$d" = / ] && return 0
    d="${d%/*}"; d="${d:-/}"
  done
}

case "$MODE" in
  reset)
    rm -f "$STATE"
    ;;
  mark)
    [ "${FP##*/}" = AGENTS.md ] && [ "$FULL" = yes ] || exit 0
    root=$(governing_root "$FP")
    [ -n "$root" ] && [ "$root/AGENTS.md" -ef "$FP" ] || exit 0
    mkdir -p "$(dirname "$STATE")" 2>/dev/null || exit 0
    grep -qxF "$root" "$STATE" 2>/dev/null || printf '%s\n' "$root" >>"$STATE"
    ;;
  enforce)
    [ -n "$FP" ] || exit 0
    root=$(governing_root "$FP")
    [ -n "$root" ] || exit 0
    grep -qxF "$root" "$STATE" 2>/dev/null && exit 0
    echo "PACS: $FP is governed by $root/AGENTS.md. Read that file in full with the Read tool (no limit or offset), then retry this edit." >&2
    exit 2
    ;;
esac
exit 0
