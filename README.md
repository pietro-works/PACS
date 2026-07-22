<p align="center">
  <img src="assets/logo.png" width="320" alt="the PACS golem coding on a mossy stone computer">
</p>

<h1 align="center">P.A.C.S | Petrus Agentic Coupling System</h1>

<p align="center"><strong>Nobody warns you which stone was holding the roof up. PACS does...</strong></p>

<p align="center">
  <img alt="license MIT" src="https://img.shields.io/badge/license-MIT-2ea44f">
  <a href="SPEC.md"><img alt="read the spec" src="https://img.shields.io/badge/spec-SPEC.md-3b82f6"></a>
  <img alt="invariants: silent only" src="https://img.shields.io/badge/invariants-silent%20only-a37b4c">
  <img alt="maintained by a golem" src="https://img.shields.io/badge/maintained%20by-a%20golem-8a8a8a">
</p>

---

## What it is

PACS is a small convention for marking the couplings in a codebase that break quietly. Each one gets a stable code (`PACS0001`, `PACS0002`, and so on), a single row in a registry, and that same code dropped as a comment on the exact line it governs. Edit near the line and the code sends you to the row listing the other places already known to need the same change, so you start from what someone found instead of from nothing.

A number, a row, a comment. That is the whole system.

## The problem it targets

Some bugs announce themselves. The build turns red, a test fails, the app throws. Those are the kind ones, because the failure is its own enforcement.

PACS is for the other kind. You add a unit type and forget the sprite table, so it renders as nothing. You rename one field on a message and the far side reads `undefined`, so the request quietly times out. You add a sound and never register it, so it plays in perfect silence forever. Nothing errors. You cut a wire and the lights go out in a room you forgot existed, and you find out weeks later when someone asks why the new thing looks broken.

A compiler cannot see that coupling. A type system usually can't either. A test catches it only when someone already knew the coupling was there, and that knowledge is exactly what evaporates between sessions, refactors, and whoever opens the file next.

## Why it works

The signpost sits at the point of edit. The warning is on the wire you are about to cut, not buried in a doc nobody reopens.

There is one source of truth. The registry row names the touch-points someone already found, which turns "where else does this reach" from a blank page into a starting list.

That list is a floor, not a ceiling, and the distinction matters more than it sounds. A written list of sites reads as a complete one, and a complete list turns an open search into a checklist: do the four named sites, feel finished, stop looking. So the row says what is known, the tag repeats that it is only what is known, and you still grep for the rest. Find one the row missed and you add it in that same change. A list that gets written back to stays true. One that only ever gets read decays quietly, which is the failure this whole convention exists to prevent, one level up.

The codes are stable and append-only. `PACS0007` means the same thing next year and in a stranger's clone. Move it during a refactor and the tag travels with the code; the number never gets reused for something else.

And it stays small on purpose. Only load-bearing, silently-failing couplings earn a code. If something breaks loudly it gets nothing, because the crash already did the job. Over-tagging is how this idea dies, so the bar to mint a code is deliberately high, and every row has to justify itself in its own words, not a stock phrase copied down the column.

The forcing function is one line at the end of a change: name the rows you actually opened, not just the codes you're claiming to have touched. A commit closes with something like `Opened PACS0001, PACS0014, confirmed touch-points in atlas.js and validate.js`, and that line is the whole audit trail, checkable against what the change actually did instead of just asserted. A reviewer reads it and knows which tripwires were considered, without rebuilding the coupling map in their own head first.

## Three real ones

These came out of one codebase, a browser game of about seven thousand lines. A single sweep found twenty-two couplings that cleared the bar. Here are three, each a different shape.

### A registry that a dozen places read

The unit types live in one constant. Adding a fourth, say a `drone`, is easy in the obvious spots. The trap is that a dozen other places are keyed by type independently and none of them derive from the source: the sprite atlas, the movement dispatch, the validator's allowlist, the build menu. Miss the atlas and the drone plays the entire match invisible. Miss the validator and every order you give it is dropped before the engine sees it.

```js
// PACS0001 — a new unit type needs matching edits at every keyed-by-type site
//            (sprite atlas, validator allowlist, movement dispatch, build cards) — AGENTS.md (known sites, not exhaustive)
const UNITS = { worker: {...}, vehicle: {...}, triangle: {...} }
```

```yaml
PACS0001:
  anchor: "engine.js:UNITS"
  sync_with:
    - "atlas.js"
    - "validate.js"
    - "dispatch.js"
    - "build.js"
  fails_silently: "new type renders blank, or its orders get dropped before the engine runs"
  justification: "four independent keyed-by-type sites, none derived from UNITS, so nothing forces them to stay in sync"
```

### A message that crosses a process boundary

The page hands a turn request to a browser extension over `postMessage`. The extension reads each field by name, with no spread. Rename `requestId` to `reqId` on the page and forget the extension, and the field arrives as `undefined` on the far side. Nothing throws. The turn times out four minutes later and looks exactly like the model failing to answer, which is the last place you will think to look.

```js
// PACS0011 — the extension reads these fields BY NAME (no spread);
//            rename here means rename there, or it arrives undefined across the boundary — AGENTS.md (known sites, not exhaustive)
window.postMessage({ __bridge: 'req', requestId: id, bot, payload }, '*')
```

```yaml
PACS0011:
  anchor: "webtab-client.js:request_envelope"
  sync_with:
    - "extension/bridge.js"
    - "extension/background.js"
  fails_silently: "a renamed field crosses as undefined, the turn silently times out"
  justification: "the two sides read fields by name across a process boundary, so a rename on one side has no compiler link to the other"
```

### A sound that plays into the void

Every sound effect is looked up in one table before it plays. Call `sfx('meltdown')` but never add `meltdown` to the table, and the lookup returns nothing and the function returns early. The siren you spent an afternoon composing plays in total silence, and your first guess will be a mute bug or a cooldown, not a missing key.

```js
// PACS0014 — every sfx(name) needs a key here, or the cue silently no-ops (permanent silence) — AGENTS.md (known sites, not exhaustive)
const SOUNDS = { chat: ..., coreHit: ..., meltdown: ... }
```

```yaml
PACS0014:
  anchor: "audio.js:SOUNDS"
  sync_with:
    - "every sfx() / play() caller"
  fails_silently: "an unregistered event plays nothing, no error, reads as a mute bug"
  justification: "the lookup fails closed with no error path, so a missing key and a muted cue are indistinguishable from outside"
```

Stack a couple dozen rows like these and you have a map of the quiet ways your own codebase can go wrong, written down where the next person, or the next agent, will actually run into it.

## Adopt it

Put a registry file somewhere durable, like `AGENTS.md`. From then on, that file gets read in full before any planning or code-touching work starts. When you hit a silent coupling, take the next free number, add a YAML row with a real justification, and tag the anchor.

One rule comes with it. Every row is what someone found, not what exists, so editing near a tag means satisfying the sites it names and grepping for the ones it doesn't. Anything you turn up goes into the row before you finish. That is it.

Use `//` in most code, `/* */` inside CSS or template strings, `<!-- -->` in markup, `#` in shell. 

## Modularity

PACS starts with zero dependencies. At its simplest, it is just `AGENTS.md` and `SPEC.md` interpreted directly by your agent. 

If you want automated verification, run `bin/pacs check` in your workspace or CI to catch dead paths and execute custom test scripts. If you use Claude Code and want pre-tool enforcement, `pacs-hooks/` provides optional middleware that blocks file edits until the registry is read. 

The linter runs only what you configure. If you have no verification scripts, it checks the YAML schema and tags. If you do not use Claude Code, you can ignore the hooks folder completely.

The full rules for minting and checking are in [SPEC.md](SPEC.md). It fits on one screen.

## The greencheck (per-output consult signal)

A long session can run many responses between one registry read and the next commit. To close this gap, `AGENTS.md` carries an instruction telling the agent to open any response with `P.A.C.S ✅` whenever that response actually drew on the registry.

It's an assertion sitting in plain view. Instead of sitting invisibly inside a context window, it sits in the transcript, where a human scrolling past can catch a green check next to a change that obviously ignored the registry, or the absence of one next to a change that clearly should have consulted it. A signal you can catch lying beats a check you can't see at all.

## What PACS is not

It is not a replacement for [Andrej Karpathy's LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f), and it isn't trying to be.

The LLM Wiki is a knowledge base that compounds. An agent reads your raw sources and compiles them into interlinked pages you can query, so understanding builds up instead of being re-derived on every question. It is a library your agent writes and keeps current, and it wants to hold everything worth knowing.

PACS stores almost nothing. It does not explain your system or teach you the domain, and it won't answer a question about either. It marks a small set of tripwires and then refuses to grow past them. The wiki remembers what is worth understanding; PACS remembers only what will hurt you without saying a word, and it counts every extra entry as clutter.

Run both and they don't fight. The wiki is how your agent understands the code. PACS is how it changes the code without quietly regressing it. One is the map of the whole territory. The other is a small red X on the three landmines in it.

## The name

PACS is the Petrus Agentic Coupling System, and yes, it is named after the person who wrote it, whose name traces back to the Greek for rock. A method about the load-bearing parts that must never quietly shift, named after a guy whose own name means "does not move." Read that as vanity or as branding, your call. It is at least accurate.

The golem is the part worth keeping. In the old stories a golem does precisely what the instructions carved into it say, no more, no less, and never once thinks it knows better. He reads the full registry before he lifts a finger, handles every touch-point on the list, and tells you exactly what he changed. Which makes him, on a good day, a more careful contributor than the man he is named after.

## License

MIT. Take it, rename it, tag your own landmines.
