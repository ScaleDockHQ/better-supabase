# 0591: Measure the type and dev-loop cost of 0.58 in the bench

- Status: accepted
- Date: 2026-11-09
- Amends: 0362, 0581, 0590

## Context

CentraKit measured develop (0.54) against the 0.58 branch on the same Next.js:
`gen` and `upgrade --check` about two times slower, and the runtime program of
`tsc` at 405k types and 0.65 s against 346k types and 0.28 s. The type bench in
`tests/types/perf` did not catch either. Its server program checked in 0.0 s on
every compiler, because it made one `list` and one `create` per table. Its `gen`
case writes only the `types` task, so it never renders the SQL modules that
`upgrade` and `gen` share through the render memo (ADR 0362).

## Measured

All numbers are from one machine with TypeScript 7.0.2, comparing the tag
`better-supabase@0.57.0` with the head of `fix/upgrade-0.58`.

**Types.** The bench's own programs are identical or within 0.1 percent:

| Program                             | 0.57.0 types | head types | 0.57.0 instantiations | head instantiations |
| ----------------------------------- | ------------ | ---------- | --------------------- | ------------------- |
| client, 250 tables, 40 queried      | 28,192       | 28,192     | 50,465                | 50,465              |
| server, `server.context()` and `db` | 23,292       | 23,296     | 43,087                | 43,117              |
| CentraKit fixture, `--checkers 1`   | 454,118      | 454,600    | 2,167,760             | 2,185,204           |

The fixture (`tests/validation-centrakit`, 2,536 and 2,576 files) must be
compared with one checker: with the default four, each checker holds its own
copy of the shared types and the totals (651,925 and 693,576) differ by how the
files were split. The trace diff of the one-checker runs shows three
additions: 3,971 types from one family in `lib.es2015.iterable.d.ts` that the
trace does not tie to a source file, 309 object types for `naming.json`
(ADR 0246 imports it), and 206 for `EntityConfig` in `config/blocks.ts`, which
is generic over `Names["entities"][E]` instead of a plain `EntityConfig` for the
former keys. The fixture's check time went from 3.1 s to 3.8 s, and the added
time sits in library source files the fixture compiles directly (114 files new
to the program, such as `sql/modules/permissions-scopes.ts` at 312 ms and then
708 ms), so it measures the fixture's reach and not the published declarations.

**`upgrade --check`.** On the CentraKit fixture the head is not slower than
0.57.0: cold 3.3 s against 5.2 s, warm 0.56 s against 5.0 s. The warm gain is
the on-disk memo of ADR 0291, which 0.57.0 does not have. A CPU profile of the
cold head run (3.85 s of samples) puts the time in garbage collection (639 ms),
`maskSql` and its `blank` helper (526 ms, called from `readGrants` and
`readPolicies` inside `applyTenantScope` and `applyActorWriteGuards`, which mask
the same module text more than once per render), comment stripping (140 ms), and
ES module resolution (214 ms in `package_json_reader`). The `has` function of
`ctx` that reads `ownColumns` costs 28 ms self time, so the lookup itself is not
the slowdown.

**Cache misses.** Adding one column to a table a block owns re-renders 30 to 36
files out of 76 (`teams`, `organization_users`, `task_tags` and `status_history`
gave 32, 36, 30 and 34), where an unrelated edit renders none. The read sets in
`modules/renders.json` show why. `ctx.has` calls `known.includes(physical)` on
the table's column array, so the tracked read is one `ownColumns.<table>[i]`
entry per column, and 26 module entries hold 678 such reads. The data-lifecycle
module asks about 27 tables, so every column edit on any owned table renders it
again, next to the 1 to 5 modules that own or read that table.

## Decision

The published types did not grow, so there is nothing to cut in `src`. The three
additions above (about 500 types in a 454,000 type program) are justified:
`EntityConfig<Names[...]>` types each block's entity keys from the naming catalog, and the `naming.json` import is the single source of names (ADR
0246). CentraKit's growth from 346k to 405k types is not reproduced here, and
the fixture is not CentraKit. To locate it, run `tsc --noEmit --checkers 1
--generateTrace` on CentraKit at 0.57.0 and on the branch, then count
`types.json` entries by symbol name and declaring file, ignoring the hash in
declaration file names.

The bench changes so it can see this class of change:

- The server program queries three times the client program's tables with the
  client's query shapes (selection, filters, ordering, two includes), an update,
  a service-role context from `contextFor`, `$rpc` and the view and the
  two-foreign-key table of the composite profile. Its check time is the smallest
  of three runs, and `benchServer` fails when that time is not above the
  calibration program's. The server program is now gated on check time too.
- Every `tsc` measurement takes the smallest check time of three runs.
- `upgrade` gets an `ownedColumn` case (rendered and written counts, which only
  shrink) and `upgrade --check` gets cold, warm and owned-column wall times,
  all gated at twice the baseline. The synthetic `gen` case stays, and it is
  described as what it is: the `types` task only.

Two changes in `src` follow from the profile and are left for the next plan,
because this change touches only the bench and the text:

- Store `ownColumns` as `Record<table, Record<column, true>>` so `ctx.has` reads
  one key. An added column then leaves every other module's read unchanged, and
  data-lifecycle reads only the columns it names.
- Memoize `maskSql` by text and mode in one render, so `readPolicies`,
  `readGrants` and `guardPolicies` mask a module's SQL once.

## Consequences

The 2 times in `gen` and `upgrade --check` is not reproduced on the fixture
against 0.57.0 and stays open for CentraKit itself, where the cache-miss
finding is the first candidate. ADR 0362's table covers edits that read
nothing the module reads; it says nothing about owned columns, and this ADR adds
that case. Time gates in the bench fail under heavy concurrent load (a run next
to another `verify` doubled every wall time), so a time failure there needs a
rerun on a quiet machine before it counts as a regression.
