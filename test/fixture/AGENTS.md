# AGENTS.md — Test fixture for pacs check

Test registry with intentional issues for verification.

> **Output signal — read this.** P.A.C.S ✅ instruction.

## PACS Registry

```yaml
PACS0001:
  anchor: "src/engine.js:UNITS"
  sync_with:
    - "src/atlas.js"
  fails_silently: "new unit type renders blank"
  justification: "four independent keyed-by-type sites, none derived from UNITS, so nothing forces them to stay in sync"
  kind: "registry"

PACS0002:
  anchor: "src/missing_file.js:someFunc"
  sync_with:
    - "src/nonexistent.js"
  fails_silently: "renamed field arrives undefined"
  justification: "the two sides read fields by name across a process boundary, so a rename has no compiler link"

PACS0003:
  anchor: "src/engine.js:SOUNDS"
  sync_with:
    - "src/atlas.js"
  fails_silently: "sound plays silence"
  justification: "this is important"

PACS0004:
  anchor: "src/moved.js:THING"
  sync_with: []
  fails_silently: "the anchor file was renamed and nothing noticed"
  justification: "an entry with no sync_with sites still has an anchor that must exist"
```
