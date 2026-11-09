# 0362: Cache each module render on the inputs it read

- Status: accepted
- Date: 2026-11-08
- Amends: 0248, 0291

## Context

ADR 0248 caches the whole `renderBlocks` result on a hash of the layout, so any
change to the layout renders all modules again. ADR 0291 measured it: an edit
that changes the layout cost the full render (about 1.4 s for the 129 modules,
0.8 s on CentraKit) and left the per-module cache open, because a module's
context did not record what it read.

## Decision

- `renderBlocks` renders each module instance through `renderModuleCached`
  (`src/sql/pipeline/module-cache.ts`). On a miss it passes the module a
  read-tracking view of the layout and of the installed names
  (`read-tracking.ts`). The entry is the files plus the reads: for each path a
  primitive's value, the kind of object (`type`), the own keys of an object
  that was enumerated (`keys`), whether a key exists (`has`, which also covers
  an absent optional), or a map or set taken whole (`whole`).
- A hit needs every recorded read to see today what it saw: the paths resolve
  in the new layout and compare equal. So an entry stays valid for any change to
  an input the module did not read, and only a changed read invalidates it.
- The view is a proxy over a stand-in target that forwards to the real value, so
  a frozen layout never breaks a proxy invariant, and nested plain objects and
  arrays are tracked the same way. A function read, a write to the input, or a
  class instance makes the render uncacheable: the files are returned and
  nothing is stored. An error thrown while tracking (`structuredClone` throws on
  a proxy) renders the real input once more, so the caller gets the render's own
  error.
- `src/sql` keeps no Node built-ins. The CLI installs the store
  (`setModuleRenderStore`) in `installMemo`: `modules/renders.json` under the
  cache folder, read once and written once when the process exits, one entry per
  module instance (at most 1024), salted with the CLI version and the generator
  hash. `--no-cache` installs none and `cache purge` removes it. The disk
  parse cache of ADR 0361 and this store share `createDiskStore`.
- The whole-render cache of ADR 0248 stays above it, so an unchanged layout
  still costs one lookup.
- `renderStats.modules` and the `upgrade` receipt count the files a render made,
  not the ones the module cache served.

## Measured

Rendering all 129 modules (184 module instances) on one machine, Node 24:

| Case                                     | Time      | Modules rendered |
| ---------------------------------------- | --------- | ---------------- |
| no store                                 | 1437 ms   | 184              |
| first render with tracking               | 1494 ms   | 184              |
| second render, nothing changed           | 72 ms     | 0                |
| `realtimeTables` changed                 | 77 ms     | 1                |
| `auditedTables` changed                  | 84 ms     | 2                |
| `customAccessTokenHook` changed          | 75 ms     | 2                |
| a second table added to `ownTables`      | 54 ms     | 0                |
| `dir`, `modules.tasks` or `seedDefaults` | 1.3-1.7 s | 184              |

Tracking costs about 4 percent on a miss. A read set holds about 315 reads.

`upgrade` on CentraKit, after one more audited table in an app file (the new
`audit` case of `tests/types/perf`): 77 files rendered before, 45 after. Time
moved from 1.2-2.5 s to 0.75-1.2 s across runs on a busy machine; the quiet
run is 0.74 s against a warm no-op of 0.43 s.

## Not done

- A column added to a table a block owns re-renders 30 to 36 files, because
  `ctx.has` reads the table's column list entry by entry (ADR 0591).
- Inputs every module reads (`dir`, `prefix`, the provider's functions, each
  block's `columns`) still render every module, because the context reads them
  while it is built. Narrowing that needs the context to read them lazily.
- The data, test and app files and the prelude are assembled after the module
  renders and are not cached per module.

## Alternatives considered

- **A hash of the whole layout per module.** This is the whole-render key and
  misses on any change.
- **Hand-written dependencies per module.** They drift from what the module
  reads; the recorded read set cannot.

## Consequences

An edit that changes one input renders the modules that read it and serves the
rest. A module that starts to read another input widens its own read set on the
next render, with no list to keep. A render that does something a proxy cannot
carry falls back to rendering without the cache.
