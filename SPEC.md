# The PACS Specification

PACS (the Petrus Agentic Coupling System) is a convention for recording load-bearing invariants: the couplings in a codebase where one edit forces a matching edit at a distant site, and missing that second edit fails silently.

This is the normative spec. For the pitch, read the [README](README.md).

## 0. Before any work

Before doing any work that involves planning, reviewing, or changing code, read the full PACS Registry table first. 

Read it as a floor, not a ceiling. The registry tells you about couplings someone already found; it tells you nothing about the ones nobody has looked for yet. Finishing the sites an entry names is the start of the job, not the end of it — grep for the rest yourself (see §3).

If there is no registry file yet, create `AGENTS.md` and bootstrap one.

This read-first convention can be trusted to the agent natively (most agents will read `AGENTS.md` automatically), or enforced via optional `PreToolUse` hooks (see `pacs-hooks/`).

## 1. What earns a code

A PACS code marks an invariant that has all three of these properties:
- **Coupled.** Adding or changing one thing requires a matching change somewhere else.
- **Distant.** That somewhere else is in another file, module, or process. 
- **Silent.** Missing the second edit produces no error, no crash, no red build. Just wrong behavior.

**What does not earn a code:**
- Anything that fails loudly (throws, or breaks a compiler).
- Local logic with no distant consumer.

## 2. The three pieces

**The code.** A stable identifier, `PACS0001` through `PACS0099`. Append-only. Never reuse a number.
**The registry.** One ````yaml` block in a durable file (`AGENTS.md`). This is the source of truth.
**The tag.** A comment (`// PACS0001`) placed at the exact anchor the invariant governs.

## 3. The YAML registry format

Instead of Markdown tables, PACS uses a machine-verifiable YAML block under a `## PACS Registry` heading. 

```markdown
## PACS Registry

```yaml
PACS0001:
  anchor: "src/engine.js:UNITS"
  sync_with:
    - "src/atlas.js"
    - "src/validate.js"
  fails_silently: "New unit type renders blank or its orders get dropped before the engine runs"
  justification: "Four independent keyed-by-type sites, none derived from UNITS, so nothing forces them to stay in sync"
  verify: "scripts/pacs/verify_0001.sh"  # Optional executable predicate
```
```

### Fields
- **anchor**: String naming the file and symbol where the tag lives.
- **sync_with**: Array of file paths that must be kept in sync. **This list is known, not exhaustive** — see below.
- **fails_silently**: The concrete wrong behavior if missed.
- **justification**: A specific consequence. Must not be generic fluff ("could break things").
- **verify** *(Optional)*: A path to an executable bash/node/python script (exit 0 = pass, non-zero = fail) that programmatically enforces the invariant.

### sync_with is a floor, not a ceiling

`sync_with` lists the touch-points that are known. It is not exhaustive. Grep for others before you finish; an entry that names four sites does not mean there are only four.

This is the single most important thing to understand about consuming an entry. A written list of sites reads as a complete list, and a complete list turns an open search into a checklist: do the four named sites, feel finished, stop looking. That failure mode is worse than having no entry at all, because the entry supplies false closure — the agent or developer who would otherwise have kept grepping now has a reason to stop.

Every registry is incomplete. Codebases grow between sweeps, sites get added by people who never read the entry, and no sweep catches everything on the first pass. Treat `sync_with` as the sites someone already found, and the grep you run yourself as the sites they missed. When you find one, add it to the entry in the same change.

## 4. The tag format

```js
// PACS0003 — <short rule> — AGENTS.md (known sites, not exhaustive)
```

Use `//` in JS/TS, `/* */` in CSS, `<!-- -->` in HTML, `#` in Python/Shell. Point the tail at wherever your registry lives.

The `(known sites, not exhaustive)` suffix is required, and it is not decoration. The tag is read far more often than the spec is — every time anyone edits near the anchor, across every session, long after whoever wrote the entry is gone. Carrying the caveat on the tag itself means the anti-closure reminder arrives at the moment of the edit, in the same glance as the rule. A tag without it silently teaches the reader that the registry row is the complete answer.

## 5. Minting

You mint a code in the same change that introduces or modifies the invariant:
1. Assign the next free number (`PACS0001`, `PACS0002`).
2. Add the row to the YAML registry.
3. Tag the anchor in the code, including the `(known sites, not exhaustive)` suffix (§4).
4. Grep the repo to find all touch-points and add them to `sync_with`. Record what you actually verified, not what you assume is complete.

**Consuming an entry carries the same obligation.** When you edit near a tag, satisfy every site the entry names *and* grep for sites it doesn't. If you find one, add it to `sync_with` in that same change. Entries decay unless the people using them keep writing back — a row that only ever gets read is a row that gets less true every month.

## 6. Numbering

`0001` to `0099` are code-enforced invariants. Each carries a tag in the source. `0100` and up are process or reasoning rules that live in prose, with no code anchor. A rule about something that must never be omitted has no line to tag when the omission is the whole problem. That belongs in the `0100`+ tier by design.

Zero-padded to four digits, so they sort and grep cleanly.

## 7. The report line and the greencheck

When you finish a change, name the PACS codes you touched or minted in your commit body or report.

**The Greencheck:** Whenever an agent consults the registry while producing a response, it opens that response with `P.A.C.S ✅` on its own line. 

## 8. Modularity and parity checks

PACS is completely modular. You only install what you want:

1. **The Core (Zero-install)**: Just `AGENTS.md` and this specification. The LLM reads the YAML and follows the rules.
2. **The Linter (Opt-in Verification)**: Run `bin/pacs check` locally or in CI. It mechanically verifies the YAML schema, catches orphaned tags, checks dead paths, and runs your optional `verify:` scripts.
3. **The Hooks (Opt-in Enforcement)**: Use `pacs-hooks/` if you use Claude Code and want to strictly block it from acting before reading the registry.

You can run `bin/pacs check` right now to verify your registry health. See `bin/pacs --help` for commands.
