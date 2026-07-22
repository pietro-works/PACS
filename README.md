<p align="center">
  <img src="assets/logo.png" width="320" alt="the PACS golem coding on a mossy stone computer">
</p>

<h1 align="center">P.A.C.S | Petrus Agentic Coding System</h1>

<p align="center"><strong>Nobody warns you which stone was holding the roof up. PACS does...</strong></p>

<p align="center">
  <img alt="license MIT" src="https://img.shields.io/badge/license-MIT-2ea44f">
  <a href="SPEC.md"><img alt="read the spec" src="https://img.shields.io/badge/spec-SPEC.md-3b82f6"></a>
  <img alt="invariants: silent only" src="https://img.shields.io/badge/invariants-silent%20only-a37b4c">
  <img alt="maintained by a golem" src="https://img.shields.io/badge/maintained%20by-a%20golem-8a8a8a">
</p>

---

## What it is

PACS is a small convention for marking the couplings in a codebase that break quietly. Each one gets a stable code (`PACS0001`, `PACS0002`, and so on), a single row in a registry, and that same code dropped as a comment on the exact line it governs. Edit near the line and the code sends you to the row that lists every other place you now have to change.

A number, a row, a comment. That is the whole system.

## The problem it targets

Some bugs announce themselves. The build turns red, a test fails, the app throws. Those are the kind ones, because the failure is its own enforcement.

PACS is for the other kind. You add a unit type and forget the sprite table, so it renders as nothing. You rename one field on a message and the far side reads `undefined`, so the request quietly times out. You add a sound and never register it, so it plays in perfect silence forever. Nothing errors. You cut a wire and the lights go out in a room you forgot existed, and you find out weeks later when someone asks why the new thing looks broken.

A compiler cannot see that coupling. A type system usually can't either. A test catches it only when someone already knew the coupling was there, and that knowledge is exactly what evaporates between sessions, refactors, and whoever opens the file next.

## Why it works

The signpost sits at the point of edit. The warning is on the wire you are about to cut, not buried in a doc nobody reopens.

There is one source of truth. The registry row names every touch-point, so "did I get all of them" has an answer instead of a feeling.

The codes are stable and append-only. `PACS0007` means the same thing next year and in a stranger's clone. Move it during a refactor and the tag travels with the code; the number never gets reused for something else.

And it stays small on purpose. Only load-bearing, silently-failing couplings earn a code. If something breaks loudly it gets nothing, because the crash already did the job. Over-tagging is how this idea dies, so the bar to mint a code is deliberately high, and every row has to justify itself in its own words, not a stock phrase copied down the column.

The forcing function is one line at the end of a change: name the rows you actually opened, not just the codes you're claiming to have touched. A commit closes with something like `Opened PACS0001, PACS0014, confirmed touch-points in atlas.js and validate.js`, and that line is the whole audit trail, checkable against what the change actually did instead of just asserted. A reviewer reads it and knows which tripwires were considered, without rebuilding the coupling map in their own head first.

## Three real ones

These came out of one codebase, a browser game of about seven thousand lines. A single sweep found twenty-two couplings that cleared the bar. Here are three, each a different shape.

### A registry that a dozen places read

The unit types live in one constant. Adding a fourth, say a `drone`, is easy in the obvious spots. The trap is that a dozen other places are keyed by type independently and none of them derive from the source: the sprite atlas, the movement dispatch, the validator's allowlist, the build menu. Miss the atlas and the drone plays the entire match invisible. Miss the validator and every order you give it is dropped before the engine sees it.

```js
// PACS0001 — a new unit type needs matching edits at every keyed-by-type site
//            (sprite atlas, validator allowlist, movement dispatch, build cards) — AGENTS.md
const UNITS = { worker: {...}, vehicle: {...}, triangle: {...} }
```

| Code | Anchor | Keep in sync with | Fails silently if missed | Justification |
|---|---|---|---|---|
| PACS0001 | `engine.js` · `UNITS` | `atlas.js` sprites, `validate` allowlist, render dispatch, build cards | new type renders blank, or its orders get dropped before the engine runs | four independent keyed-by-type sites, none derived from `UNITS`, so nothing forces them to stay in sync |

### A message that crosses a process boundary

The page hands a turn request to a browser extension over `postMessage`. The extension reads each field by name, with no spread. Rename `requestId` to `reqId` on the page and forget the extension, and the field arrives as `undefined` on the far side. Nothing throws. The turn times out four minutes later and looks exactly like the model failing to answer, which is the last place you will think to look.

```js
// PACS0011 — the extension reads these fields BY NAME (no spread);
//            rename here means rename there, or it arrives undefined across the boundary — AGENTS.md
window.postMessage({ __bridge: 'req', requestId: id, bot, payload }, '*')
```

| Code | Anchor | Keep in sync with | Fails silently if missed | Justification |
|---|---|---|---|---|
| PACS0011 | `webtab-client.js` · request envelope | `extension/bridge.js`, `extension/background.js` | a renamed field crosses as `undefined`, the turn silently times out | the two sides read fields by name across a process boundary, so a rename on one side has no compiler link to the other |

### A sound that plays into the void

Every sound effect is looked up in one table before it plays. Call `sfx('meltdown')` but never add `meltdown` to the table, and the lookup returns nothing and the function returns early. The siren you spent an afternoon composing plays in total silence, and your first guess will be a mute bug or a cooldown, not a missing key.

```js
// PACS0014 — every sfx(name) needs a key here, or the cue silently no-ops (permanent silence) — AGENTS.md
const SOUNDS = { chat: ..., coreHit: ..., meltdown: ... }
```

| Code | Anchor | Keep in sync with | Fails silently if missed | Justification |
|---|---|---|---|---|
| PACS0014 | `audio.js` · `SOUNDS` | every `sfx()` / `play()` caller | an unregistered event plays nothing, no error, reads as a mute bug | the lookup fails closed with no error path, so a missing key and a muted cue are indistinguishable from outside |

Stack a couple dozen rows like these and you have a map of the quiet ways your own codebase can go wrong, written down where the next person, or the next agent, will actually run into it.

## Adopt it in about a minute

Put a registry table somewhere durable, an `AGENTS.md` or an `ARCHITECTURE.md`, whatever your agents already read. From then on, that table gets read in full before any planning or code-touching work starts, not just consulted when a coupling happens to come up. When you hit a silent coupling, take the next free number, add a row with a real justification, and tag the anchor. That is it.

Use `//` in most code, `/* */` inside CSS or template strings, `<!-- -->` in markup, `#` in shell. Files that can't hold a comment, like JSON, live in the registry only. Numbering runs `0001`–`0099` for codes that carry a tag in the source, and `0100`+ for process notes that stay in the guide.

The full rules, minting, consuming, numbering, and the parity check that keeps the registry honest, a check your agent walks by hand, not a bundled script, are in [SPEC.md](SPEC.md). It fits on one screen.

Section 0's "read before you touch anything" is, by default, a convention the agent follows because it's told to, not because anything forces it. If you'd rather it be enforced than trusted, `pacs-hooks/` has three small Claude Code hooks that block any edit until `AGENTS.md` has actually been read this session, and clear that requirement again after a compaction. Optional, install steps in `pacs-hooks/INSTALL.md`.

## The hooks have a ceiling, so there's a second signal

Even with the hooks installed, there's a gap they can't close. A `PreToolUse` hook only sees tool calls. It can block an `Edit` until `AGENTS.md` has been read, but it has no view into a plain response, a plan, or any output that never touches the file system. The hook proves the registry got read before code changed. It can't prove the agent actually used what was in it, and it says nothing at all about the stretch of conversation between one read and the next commit.

The fix in this repo is small and a little inelegant on purpose: `AGENTS.md` carries an instruction telling the agent to open any response with `PACS ✅`, on its own line, whenever that response actually drew on the registry. No mark, no claim. It's a workaround, not a proof, closer to a gambiarra than an engineered fix, since the agent could in principle print the check without having read a thing. But that was true of every prose-only rule in this spec already. What the mark changes is where the lie has to live. Instead of sitting invisibly inside a context window, it sits in the transcript, next to the work it's supposedly attached to, where a human scrolling past can catch a green check next to a change that obviously ignored the registry, or the absence of one next to a change that clearly should have consulted it.

Section 7's report line closes this out after the fact, at the level of a whole change. The greencheck runs underneath it, at the level of a single response, and the two together are the closest this spec gets to covering both the moment of edit and everything around it. Full reasoning for why this exists and what it doesn't claim to do is in [SPEC.md section 7.1](SPEC.md#71-the-greencheck-per-output-consult-signal).

## What PACS is not

It is not a replacement for [Andrej Karpathy's LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f), and it isn't trying to be.

The LLM Wiki is a knowledge base that compounds. An agent reads your raw sources and compiles them into interlinked pages you can query, so understanding builds up instead of being re-derived on every question. It is a library your agent writes and keeps current, and it wants to hold everything worth knowing.

PACS stores almost nothing. It does not explain your system or teach you the domain, and it won't answer a question about either. It marks a small set of tripwires and then refuses to grow past them. The wiki remembers what is worth understanding; PACS remembers only what will hurt you without saying a word, and it counts every extra entry as clutter.

Run both and they don't fight. The wiki is how your agent understands the code. PACS is how it changes the code without quietly regressing it. One is the map of the whole territory. The other is a small red X on the three landmines in it.

## The name

PACS is the Petrus Agentic Coding System, and yes, it is named after the person who wrote it, whose name traces back to the Greek for rock. A method about the load-bearing parts that must never quietly shift, named after a guy whose own name means "does not move." Read that as vanity or as branding, your call. It is at least accurate.

The golem is the part worth keeping. In the old stories a golem does precisely what the instructions carved into it say, no more, no less, and never once thinks it knows better. He reads the full registry before he lifts a finger, handles every touch-point on the list, and tells you exactly what he changed. Which makes him, on a good day, a more careful contributor than the man he is named after.

## License

MIT. Take it, rename it, tag your own landmines.
