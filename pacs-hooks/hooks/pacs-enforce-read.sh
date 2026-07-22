#!/bin/bash
# Resolve the project from the hook payload's cwd, falling back to this
# script's own location. That fallback covers a per-project install (hooks
# live at <project>/.claude/hooks/, so ../.. is the project root); the payload
# covers a global install in ~/.claude/settings.json, where the script's path
# says nothing about which project is being edited. One copy of this script
# serves both. Never trust CLAUDE_PROJECT_DIR — some entrypoints (Cowork,
# desktop) leave it unset.
HOOK_INPUT=$(cat)
PROJECT_DIR=$(printf '%s' "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[[ -n "$PROJECT_DIR" && -f "${PROJECT_DIR}/AGENTS.md" ]] \
  || PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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
  echo "Read this project's AGENTS.md in full before editing code (the PACS Registry lives there — see SPEC.md section 0). Use the Read tool on AGENTS.md, with no limit or offset, then retry this edit." >&2
  exit 2
fi

exit 0
