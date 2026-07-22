# AGENTS.md — Clean test fixture (all checks should pass)

## PACS Registry

```yaml
PACS0001:
  anchor: "src/engine.js:UNITS"
  sync_with:
    - "src/atlas.js"
  fails_silently: "new unit type renders blank or its orders get dropped before the engine runs"
  justification: "four independent keyed-by-type sites, none derived from UNITS, so nothing forces them to stay in sync"
```
