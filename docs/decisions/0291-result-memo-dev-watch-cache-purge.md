# 0291: Memoize the adoption scan on disk, watch with `dev`, and purge the cache with `cache purge`

- Status: accepted; builds on 0248 and 0109
- Date: 2026-11-07

## Context

A warm `upgrade` on the CentraKit fixture took 7.5 s on the stage 2 baseline
machine, as long as a cold one, and `gen --watch` polled modification times. A
profile of the warm run showed where the time went: 60 percent was
`moduleLayoutFor`, which renders every block's body once more to learn which
columns the blocks write as text (`adoptedTables`), before the render cache is
even consulted. `entityRenamePlan` then rendered all blocks a second time to
read their `@bsb-names` markers, although `upgrade` had just rendered them.

The plan for Part 7 asks for a per-module render cache with read tracking, a
parse cache, a worker pool and a watch loop. This change delivers what the
profile pays for and that does not touch the block SQL modules, which another
change is editing.

## Decision

- **`memoized(namespace, parts, accept, compute)`** (`src/sql/result-memo.ts`)
  computes a derived result once per input: from memory, then from a store the
  CLI installs, then fresh. The key covers `parts` and the generator (CLI
  version and a hash of its files). A part with a function makes the call
  compute every time, as the render key already does. The state sits on
  `globalThis`, because the bundle holds the module twice (the `./sql` entry and
  the CLI chunks) and both copies must share the backend.
- **The store** (`src/cli/cache/memo-backend.ts`) keeps `memo/<namespace>.json`
  under `node_modules/.cache/better-supabase`: one file per namespace with its
  last 48 results, written to a temporary file and renamed. `run()` installs it
  after the config loads, and `--no-cache` installs none and clears memory.
  `adoptedTables` memoizes the configured and default write scans and each
  block's text columns this way.
- **`entityRenamePlan`** takes the files `upgrade` already rendered.
- **`dev`** replaces `gen --watch`. It listens for file events (`fs.watch`,
  recursive, 100 ms debounce) on the config file, `supabase/schemas` and the
  task inputs, polls every `--interval` as the fallback, prints `Ready` once on
  stderr, and runs the tasks the change affects. A changed app schema file
  reruns the tasks after `types`; the render cache and the memo make that cheap.
  `gen --watch` and `gen --interval` exit 2 with `flag_renamed`.
- **`cache purge [--dry-run]`** deletes the cache folder and reports the entries
  and bytes. `--no-cache` stays on the commands that render modules.
- **The benchmark** (`tests/types/perf/bench.ts`) purges the cache before the
  cold run, settles the tree with an unmeasured run, counts rendered modules
  from the command's own report (`data.cache.rendered`), and takes
  `BENCH_ONLY=upgrade` for work on the generator alone.

Measured on one machine (calibration ts6 0.11 s), `upgrade` on CentraKit:

| Case                   | Before                                      | After                         |
| ---------------------- | ------------------------------------------- | ----------------------------- |
| cold (cache purged)    | 1.31 s                                      | 0.95 s                        |
| warm no-op             | 1.43 s, 77 modules rendered, 1 file written | 0.36 s, 0 rendered, 0 written |
| edit of one app file   | 1.35 s, 77 rendered                         | 0.36 s, 0 rendered            |
| edit that adds a table | not measured                                | 0.82 s, whole render redone   |

The `gen` cases already sat near the 0.4 s start-up floor on this machine and
did not move.

## Not done

- **A per-module render cache with read tracking.** The whole-render cache
  (0248) answers an edit that leaves the layout unchanged, but an edit that adds
  a table redoes every module. A per-module cache needs the module context to
  record what it reads, which means changing context and module internals that
  the block SQL work is editing.
- **A disk parse cache per file hash.** After the memo, parsing the schema files
  costs about 10 percent of a warm run, which does not pay for a second store.
- **A worker pool.** Rendering is one synchronous pass over every module, and
  the layout can hold functions that structured clone cannot copy. The pool
  needs the per-module API above first.
- **`gen.watchInterval` to `dev.pollInterval`**, and `spec emit --watch`, which
  still polls.

## Alternatives considered

- **Cache `moduleLayoutFor` as a whole.** Its input includes every schema file,
  so any edit would miss. The memoized part depends only on the config and the
  table map, which an edit to an app file seldom changes.
- **A module-level variable for the backend.** The bundle's two copies of the
  module would not share it, and the cache would silently stay off.

## Consequences

A warm `upgrade` or `doctor` is a few small file reads, and the CLI start-up is
the floor. A change to the generator, the config or the table map recomputes the
scan once. `dev` reacts to a saved file in about a tenth of a second. The
remaining cost of a layout change is the whole render, which the per-module cache
would remove.
