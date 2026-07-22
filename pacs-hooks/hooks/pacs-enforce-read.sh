#!/bin/bash
# Self-locate the project root from this script's own path — never trust an
# env var that some entrypoints (Cowork/desktop) leave unset. Hooks always live
# at <project>/.claude/hooks/, so ../.. from here IS the project root.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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

# Count markdown table rows that start with '|'. A well-formed empty table has
# exactly two such lines (the header and the |---| separator). Two or fewer
# means no data rows: nothing to consult, so allow the edit.
pipe_lines=$(grep -cE '^[[:space:]]*\|' "$REGISTRY" 2>/dev/null || echo 0)
[[ "$pipe_lines" -le 2 ]] && exit 0

# Populated registry: require that it was actually read this session.
if [[ ! -f "$MARKER" ]]; then
  echo "Read this project's AGENTS.md in full before editing code (the PACS Registry table lives there — see SPEC.md section 0). Use the Read tool on AGENTS.md, then retry this edit." >&2
  exit 2
fi

exit 0
