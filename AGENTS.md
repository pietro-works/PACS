# AGENTS.md

Registry of load-bearing invariants for this repo, following PACS (see [SPEC.md](SPEC.md)).

The YAML block below is the source of truth. It's empty because this repo has no coded invariants yet. A new entry gets added the moment a `PACS####` code is minted — see SPEC.md §5 for the minting obligation.

> **Output signal — read this.** Whenever you consult this registry while producing a response, put `P.A.C.S ✅` on its own line at the very top of that response, before anything else. It is a visible, per-output confirmation that the registry was actually read and applied. Only print it when you genuinely consulted the table for that output — a checkmark you didn't earn is worse than none, because it makes the signal a lie.

## PACS Registry

```yaml
# Empty registry — mint codes per SPEC.md §5
#
# sync_with lists the touch-points that are known. It is not exhaustive.
# Grep for others before you finish; an entry that names four sites does
# not mean there are only four. Found a new one? Add it in the same change.
#
# Example:
# PACS0001:
#   anchor: "src/example.ts:functionName"
#   sync_with:              # KNOWN sites, not exhaustive
#     - "src/other.ts"
#   fails_silently: "describe the silent failure"
#   justification: "concrete, specific reason unique to this coupling"
```
