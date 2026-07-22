# Installing the PACS read-enforcement hooks

Three files, one config block. This is the harness-level fix from the SPEC.md
section 0 disclaimer: it doesn't make the model remember to read AGENTS.md,
it makes editing impossible until it does.

## What it does

- `pacs-reset-marker.sh` (`SessionStart`, every source: startup, resume,
  clear, fork, **and compact**) deletes a marker file.
- `pacs-mark-read.sh` (`PostToolUse` on `Read`) recreates that marker the
  moment Claude actually reads `AGENTS.md`.
- `pacs-enforce-read.sh` (`PreToolUse` on `Edit|Write|MultiEdit`) blocks the
  tool call with exit code 2 if the marker isn't there, and tells Claude
  exactly what to do about it.

Net effect: Claude cannot edit a file — in this session, or in the first
edit after a compaction resets things — without a real `Read` tool call on
`AGENTS.md` happening first. Not a claim in a report line. An actual call.

## Install

1. Copy the three scripts into your project:

   ```
   your-project/.claude/hooks/pacs-reset-marker.sh
   your-project/.claude/hooks/pacs-mark-read.sh
   your-project/.claude/hooks/pacs-enforce-read.sh
   ```

2. Make them executable:

   ```
   chmod +x your-project/.claude/hooks/pacs-*.sh
   ```

3. Merge the contents of `settings.json` into
   `your-project/.claude/settings.json`. If you already have a `hooks` block
   (for a formatter, a linter, etc.), merge at the event level — add these
   three event entries alongside whatever you already have, don't overwrite
   the file wholesale.

4. Requires `jq` on your machine (used by `pacs-mark-read.sh` to parse the
   tool-call JSON). Most systems have it; if not, `brew install jq` /
   `apt install jq`.

5. Restart or start a new Claude Code session in the project. Try editing a
   file before reading `AGENTS.md` — you should see the edit get blocked
   with the PACS0100 message. Read `AGENTS.md`, then the next edit goes
   through.

## Known gaps, stated plainly

- **This only gates `Edit`, `Write`, and `MultiEdit`.** If Claude modifies a
  file through `Bash` instead (a heredoc, `sed -i`, sending output through
  `>`), this hook doesn't see it, because it isn't one of the matched tool
  names. Claude Code's default behavior favors the file-editing tools for
  this, so it's a real but secondary gap. If you find your agent routing
  around it through Bash, the fix is a second `PreToolUse` hook matched to
  `Bash` with an `if` filter on write-shaped subcommands, at the cost of
  more false positives to tune.
- **This doesn't gate planning.** Section 0 also asks for a read before
  *planning*, not just before edits — a hook can't block "Claude is about
  to reason about an approach," only actual tool calls. The hook closes the
  half of the gap that has teeth (code doesn't change without a read); the
  planning half is still a prose convention, same as the rest of the spec.
- **The marker is file-existence, not content-hash.** It records "AGENTS.md
  was read," not "AGENTS.md was read *and the model actually used what it
  found*." That second half was never mechanically enforceable and isn't
  claimed here — real enforcement of *use* is the report line (SPEC §7) and
  the parity check (§9), which are human-auditable, not the hook.

Two behaviors worth knowing:

- **Only this project's registry satisfies the gate.** `pacs-mark-read.sh`
  matches the exact path `${PROJECT_DIR}/AGENTS.md`, not any file that
  ends in `AGENTS.md`. Reading a global `~/.claude/AGENTS.md` or another
  repo's registry will *not* clear the block. If your registry lives in a
  different file, change the `REGISTRY` variable in both
  `pacs-mark-read.sh` and `pacs-enforce-read.sh`.
- **It fails open when there's nothing to read.** If `AGENTS.md` doesn't
  exist yet, or its table has zero data rows (header + `|---|` separator
  only), edits are allowed without a read. This is what stops a fresh or
  empty repo from deadlocking every edit behind a ritual read of an empty
  file. The gate only bites once the registry actually has rows.
- **It does not depend on `CLAUDE_PROJECT_DIR`.** Some entrypoints (the
  desktop app / Cowork) leave that variable empty, which used to silently
  disable the whole gate — the paths resolved to `/` and the enforce hook
  found no registry, so it failed open and never blocked. Each script now
  self-locates the project root from its own path
  (`$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)`), and the
  `settings.json` commands are cwd-relative (`.claude/hooks/...`). The one
  remaining assumption is that hooks run with the working directory at the
  project root, which every current entrypoint does. If that ever fails the
  script just isn't found and the gate no-ops — it can never wrongly block
  an edit.
