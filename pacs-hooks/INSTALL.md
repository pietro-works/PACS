# Installing the PACS read gate

The gate makes an edit impossible until the registry that governs the edited file has been read in full. It doesn't make the model use what it read; it makes sure the text was in front of it.

## What it does

All logic lives in `hooks/pacs-gate.sh`. The three `pacs-*.sh` files next to it are two-line wrappers that call it with a mode, so existing settings keep working.

- **reset** (`SessionStart`, every source, including compaction) forgets what the session has read.
- **mark** (`PostToolUse` on `Read`) remembers a registry once it has been read in full.
- **enforce** (`PreToolUse` on `Edit|Write|MultiEdit`) exits 2 while the governing registry is unread, and names the file to read.

The governing registry of a file is the nearest `AGENTS.md` with at least one `PACS####:` entry at or above it. The climb stops at the first folder holding `.git`, so a nested repo or worktree is its own project. A file with no governing registry is never gated, and neither is a project whose registry is empty.

A read counts only when it returned the whole file: it started at line 1, returned every line, and was not cut by the token cap. If the payload has no response details, a read with `limit` or `offset` does not count.

Reads are remembered per session id, in `~/.cache/pacs/read-<session id>` (set `PACS_STATE_DIR` to move it). Nothing is written inside projects.

## Install

Point `~/.claude/settings.json` at the scripts, run in place:

```json
"SessionStart": [{"hooks": [{"type": "command", "command": "bash \"/abs/path/to/pacs-hooks/hooks/pacs-reset-marker.sh\""}]}],
"PostToolUse":  [{"matcher": "Read", "hooks": [{"type": "command", "command": "bash \"/abs/path/to/pacs-hooks/hooks/pacs-mark-read.sh\""}]}],
"PreToolUse":   [{"matcher": "Edit|Write|MultiEdit", "hooks": [{"type": "command", "command": "bash \"/abs/path/to/pacs-hooks/hooks/pacs-enforce-read.sh\""}]}]
```

Merge at the event level if you already have hooks there. Calling through `bash` means the scripts don't need an executable bit, which some synced folders drop. The gate needs `jq`; without it every call is allowed.

To check it, edit a file in a project with registry entries before reading `AGENTS.md`. The edit is refused with a message naming the registry. Read it, retry, and the edit goes through.

## Known gaps

- **Only `Edit`, `Write` and `MultiEdit` are gated.** A write through `Bash` (a heredoc, `sed -i`, a `>` redirect) is not seen.
- **Planning isn't gated.** A hook can stop a tool call, not a line of reasoning.
- **Reading isn't using.** The gate proves the registry was read, not that it was applied. The report line (SPEC §7) covers use.
- **Subagents share the session.** A subagent carries its parent's session id, so it passes on the parent's read. A subagent's compaction fires `SessionStart` without an agent id, so it resets the whole session and the parent reads again.
- **A typed `/command` doesn't pass through the tool hooks.** The next edit is still gated.
