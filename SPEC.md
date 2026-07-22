# The PACS specification

PACS (the Petrus Agentic Coding System) is a convention for recording load-bearing invariants: the couplings in a codebase where one edit forces a matching edit at a distant site, and missing that second edit fails silently. This is the normative spec. For the pitch, read the [README](README.md).

## 0. Before any work

Before doing any work that involves planning, reviewing, or changing code, read the full PACS Registry table first, and let its contents inform the approach taken. This applies at the start of a new task, and again whenever returning to code-related work after a break in that work, not just once per session. Planning is not exempt. A plan built without reading the registry can commit to an approach that ignores a coupling nobody flagged, and by the time that surfaces in the code it is already expensive to unwind. Read the table, then proceed informed.

If there is no table to read yet — no registry file at all, or one without a `## PACS Registry` table — create it with an empty table (header only) and proceed; the read-first rule binds only once a table exists, so a missing registry is a cue to bootstrap one, never a reason to stall.

Past roughly 30 rows, default to reading only the Code and Anchor columns for the full table, and pull a row's full detail, touch-points, fails-silently note, justification, only once it looks relevant to the task at hand.

This section is enforced by being read, not by any mechanism that guarantees it gets read. A model can lose track of whether it already happened, especially across a compacted or summarized context, and no wording placed here can force a re-read on its own. Where your environment supports pre-tool hooks, wiring a `PreToolUse` check that blocks edit-type tool calls until the registry file has been read this session — cleared on every `SessionStart`, including a session start triggered by compaction — closes this mechanically instead of relying on the model's memory of having done it. Where that isn't available, this section is a best-effort convention, not a guarantee.

## 1. What earns a code

A PACS code marks an invariant that has all three of these properties:

- **Coupled.** Adding or changing one thing (a producer, a type, a message, a field, a constant) requires a matching change somewhere else.
- **Distant.** That somewhere else is in another function, module, file, or process. Not the line below. Somewhere a careful editor would plausibly miss, because nothing local points to it.
- **Silent.** Missing the second edit produces no error, no crash, no red build. Just wrong or dead behavior that shows up later.

All three, or it does not get a code.

The canonical shapes:

- a hardcoded allowlist or registry that a consumer reads, and a new producer that has to be added to it.
- a constant duplicated across modules that must move together.
- an id, naming, or format convention that two sides have to agree on.
- a cross-process or cross-iframe message contract.
- a determinism requirement, where a path that must reproduce cannot use wall-clock time or randomness.

### What does not earn a code

- Local logic with no distant consumer.
- Anything that fails loudly. If forgetting the second edit throws or turns the build red, the crash is already the enforcement. Leave it alone.
- One-off values used in exactly one place.

Over-tagging is how PACS dies. A registry full of noise is a registry nobody reads. The bar is high on purpose, and section 3's justification field is what holds that bar in place, not just this warning.

If the coupling can be removed instead, by centralizing a duplicated constant, sharing a type, or making the miss fail loudly, do that first. Mint a code only when the duplication or distance can't be collapsed.

## 2. The three pieces

**The code.** A stable identifier, `PACS0001` through `PACS0099` and up. Append-only. Once a number is assigned it is never reused or renumbered, even if the invariant is later removed. Retire the row, keep the number dead.

**The registry.** One table, in a durable file your contributors and agents already read (`AGENTS.md`, `ARCHITECTURE.md`, or your equivalent). This is the source of truth. Every code has exactly one row.

**The tag.** A comment carrying the code, placed at the exact anchor the invariant governs. This is the signpost. It does not restate the whole rule. It points back to the registry.

The registry is what a fresh context reloads. The tag is what stops you mid-edit.

## 3. The registry row

Each row carries at least these five fields:

| Field | Meaning |
|---|---|
| Code | `PACS####` |
| Anchor | the file and symbol where the tag lives |
| Keep in sync with | every distant touch-point that has to change together |
| Fails silently if missed | the concrete wrong behavior, so the stakes are legible |
| Justification | one sentence, concrete, naming the actual consequence in this codebase. Not "this is important" or "could break things." A justification that could be pasted into any other row without editing it has not justified anything, and does not hold up under the parity check in section 9. |

Add a kind, a date, or notes if it helps you. Keep the five above no matter what.

The justification field is the cheap version of the bar in section 1. It doesn't require tooling to enforce, it requires the agent, at minting time and again at every parity pass, to actually answer the question rather than assert that an answer exists.

## 4. The tag format

```
// PACS0003 — <short rule> — AGENTS.md
```

Comment syntax follows the file it lives in:

| File | Syntax |
|---|---|
| JS, TS, and other C-like | `// PACS0003 — … — AGENTS.md` |
| CSS, or inside a template string | `/* PACS0003 — … — AGENTS.md */` |
| HTML, XML, Markdown | `<!-- PACS0003 — … — AGENTS.md -->` |
| Shell, Python, YAML | `# PACS0003 — … — AGENTS.md` |
| JSON and other comment-less formats | no tag; the registry row covers it |

Point the tail at wherever your registry lives. One anchor can carry more than one code when two invariants genuinely meet on the same line.

## 5. Minting (the same-change obligation)

You mint a code in the same change that introduces or modifies the invariant. Not as a follow-up, not "later." In that one edit you must:

1. Assign the next free number. Append-only, never reuse.
2. Add a registry row: rule, anchor, touch-points, silent-failure consequence, and a justification specific to this coupling.
3. Tag the anchor in code.
4. If the repo has no registry yet, bootstrap one. Add a `## PACS Registry` table to a durable file instead of skipping.
5. Run one grep for the new identifier or constant across the repo. Any hit outside the anchor is a touch-point you must add to the row before the change is done. A same-name grep only catches other code spelling the name the same way, so also grep for the literal value, or for the field or column name it maps to underneath, since a second implementation usually still shares that even when the variable name differs.

When the change adds a new entry to an existing keyed structure, a dict, a switch, an enum, a registry of any kind, grep for one of the existing sibling keys already in that structure and see how many places it turns up. If `worker` and `vehicle` each appear in four files but your new `drone` only appears in one, that gap is the signal: the other three files are touch-points nobody added yet.

A companion tool, [jscpd](https://jscpd.dev), can supplement this by flagging copy-pasted logic that reimplements something the grep alone would miss. It catches near-identical code with renamed variables well. It does not catch a rewrite that reaches the same outcome through different structure or naming, that case is still on you to notice by inspection.

Comment-less files get step 2 only, and the row should say the file is registry-covered.

Renaming or moving a tagged anchor is part of the edit, not a follow-up. Update the row's anchor field in the same change, or the next parity pass will read it as drift.

## 6. Consuming

Before you edit near a tag, open its row and satisfy every touch-point it lists.

When you add a new unit of an existing kind, another module of a known type, another provider, another action, walk the registry top to bottom and confirm each applicable code's touch-points are handled. Section 0 already put the table in front of you before this work started. This step is where that reading actually gets applied line by line, not skimmed once and set aside.

## 7. The report line

When you finish a change, name the PACS codes you touched or minted. One line, in the commit body or your agent's report.

Name which rows were actually opened and read, not only which codes are being claimed as touched. "Codes touched: PACS0001, PACS0014" asserts an outcome. "Opened PACS0001, PACS0014, confirmed touch-points in atlas.js and validate.js" is falsifiable against the rest of the report, someone can check whether those files were in fact edited.

This is the forcing function. It is the difference between "I think I caught the couplings" and a reviewer who can see exactly which ones were checked. If the line is honest, the work happened.

### 7.1 The greencheck (per-output consult signal)

The report line above closes a change. The greencheck closes an output, and it exists because those are not the same moment. A long session can run many responses between one registry read and the next commit, and section 0's read-first rule has no way to show up in that gap except as an unverifiable claim about something that happened earlier in the conversation.

Put a short instruction in the registry file itself, near the table: whenever the agent actually consults the table while producing a given response, that response opens with `PACS ✅` on its own line, before anything else. Nothing prints when the table wasn't consulted for that output. A response that never touched the registry stays unmarked, and an unmarked response is not an error, it just means this particular output didn't need the table.

Treat it the same way you'd treat a stated line count or a claimed file read: as an assertion sitting in plain view, not a mechanical guarantee. The agent could print the mark without having actually opened the table, the same way it could write the section 7 report line without having actually opened the rows it names. Nothing about the convention stops that. What it does is move the claim out of an invisible internal state and onto the page, where a human reading along can notice a run of green marks that don't match the work being described, or a change that clearly touched a keyed structure with no mark in sight, and ask about it in the moment instead of finding out during a parity pass. A signal you can catch lying beats a check you can't see at all.

This is a convention, not a hook. Nothing in the harness verifies the mark, the same ceiling section 0 already names for the read-first rule generally. Where a `PreToolUse` hook exists per section 0, the hook still does the only mechanical work here: it blocks the edit tool call itself. The greencheck adds a second, independent thing the hook cannot give you, which is a visible trace on every output, edit-shaped or not, that a human can hold up against what actually happened.

## 8. Numbering

- `0001` to `0099`: code-enforced invariants. Each carries a tag in the source.
- `0100` and up: process or reasoning rules that live in prose in the guide, with no code anchor.

A rule about something that must never be omitted, always invalidate this cache, never let a z-index cross this value, has no line to tag when the omission is the whole problem. That belongs in the `0100`+ tier by design, not a failure of the tagging system to find an anchor.

Zero-padded to four digits, so they sort and grep cleanly.

## 9. Parity

Parity is a described behavior, not a bundled tool. It's a standing check the agent performs directly, walking the registry and the codebase by hand and comparing what it finds.

Perform this check before finishing any change that added, removed, or modified a PACS code, and periodically otherwise, whenever the registry's health hasn't been confirmed in a while. To do it:

1. Read every `PACS####` code listed in the registry table.
2. Search the codebase for every `PACS####` tag actually present in source.
3. Compare the two sets by name, not by memory of what should be there.
4. For any code touched or minted in the current change, diff the files actually edited against that row's touch-points, confirming the edit reached every listed site, not just that the row and tag still exist somewhere in the codebase.

Step 4 is the one that catches a skipped read. A row and its tag can both still be present and consistent with each other while the current change quietly ignored what the row said to do, nothing orphaned, nothing dangling, steps 1 through 3 would find no problem. Step 4 is what catches it, by checking the change itself against the row instead of only checking the registry against the code at large.

Three kinds of drift to catch, none of them loud:

- **An orphaned row.** A registry entry with no matching tag anywhere in the code. The tagged line was deleted, moved, or edited without its comment being carried along, or the row was minted but the tag never got placed. The map now describes territory that doesn't exist.
- **A dangling tag.** A tag in the code with no registry row. Someone added a `PACS####` comment without minting it properly, or copied a tagged block without carrying its row along. The territory now has a marker the map doesn't know about.
- **A hollow justification.** A row that exists, matches a real tag, but whose justification field doesn't actually say anything, generic language that could apply to any coupling in any codebase. This is drift too. A code with no real justification hasn't earned its place any more than a dangling tag has, it just hasn't been caught yet.

When any of these turn up, name the mismatch and resolve it before the work is considered done: add the missing row, add the missing tag, remove what's dead, or rewrite the justification until it says something specific to this coupling. Do not let a found mismatch pass silently. That would be the exact failure PACS exists to prevent, just happening one level up, inside PACS's own bookkeeping instead of the code it's meant to protect.

## 10. Re-reading across a compressed context

Do not act on a remembered summary of a registry row if the conversation's context has been compressed or summarized since that row was last actually read. Memory of a paraphrase is not the same as the row. When a PACS code is relevant to the task at hand, re-open the registry and read the row directly, regardless of what a prior summary in context claims it said. Section 0 already makes this close to automatic, since the table gets read fresh before any code-touching work begins, this section just makes explicit that a stale recollection never substitutes for that fresh read.
