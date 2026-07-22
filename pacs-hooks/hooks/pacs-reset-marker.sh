#!/bin/bash
# Self-locate the project root from this script's own path — never trust an
# env var that some entrypoints (Cowork/desktop) leave unset. Hooks always live
# at <project>/.claude/hooks/, so ../.. from here IS the project root.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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
