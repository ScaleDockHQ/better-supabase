# 0644: Compare the mapper on the same program, read app columns per table, and measure the block set

- Status: accepted
- Date: 2026-11-10
- Amends: 0591, 0631, 0632, 0605

## Context

ADR 0632 recorded that the TypeScript 7.1 content mapper costs 4.2 times the instantiations of a
plain run at 1,200 tables and 4.3 times on the `centrakit` profile, and left the cause open. ADR
0631 left 30 module renders on an owned-column edit, which it put on whole-array reads in
`app-tables` and `view-columns`. ADR 0605 left the lazy block decision open because the block set
was never isolated on one route.

## Decision

The mapper does not cost more. The bench compared two different programs: the files runs imported
`Database` from `database.types.ts`, the plain `supabase gen types` type, and the mapper run
imported it from `generated.ts`, which wraps it in `EnrichDatabase` (the CHECK unions and typed
jsonb). `createClient<Database>` makes `supabase-js` resolve every table's `Row`, `Insert` and
`Update` through that wrapper, which is the whole difference. Both consumers now import `Database`
from `generated.ts`, so files and mapper modes check the same program.

| Profile (instantiations) | Files, before | Files, after | Mapper, before | Mapper, after | Mapper over files |
| ------------------------ | ------------- | ------------ | -------------- | ------------- | ----------------- |
| `centrakit`, ts7.1       | 50,139        | 215,716      | 216,193        | 216,193       | 4.3 then 1.00     |
| `real`, ts7.1            | 250,639       | 1,047,016    | 1,047,493      | 1,047,493     | 4.2 then 1.00     |

The files numbers rose because the program now includes the enriched type, not because the
library changed. `bench.ts` takes `BENCH_ONLY=<profile>` to run one profile.

The enriched type is the cost to look at. Removing the `createClient<Database>` line takes the
`centrakit` consumer from 215,877 to 45,899 instantiations. A variant of `Override` written as
`Omit<R, keyof O> & { [K in keyof O & keyof R]: ... }` measured 156,728 instead of 216,354, but
the second mapped type is not homomorphic and would make the optional `Insert` and `Update`
columns required, so it is not shipped.

The 30 renders of an owned-column edit did not come from whole-array reads. A log of the failed
reads of each cached module showed `keys:appColumns` on 14 modules: `hasAppColumns` in
`extra-columns.ts` read `Object.keys(layout.appColumns).length`, so the first `alter table ... add
column` in an app file (which adds the table's key) changed the read of every module that resolves
extra columns. `resolveExtraColumns` and `appExtraColumns` now look up only the table's own entry.
The output is the same. `upgrade` on the CentraKit fixture, owned-column case: 30 modules
rendered before, 4 after, with the same file written. The `new Set(layout.ownColumns[table])`
reads in `app-tables` and `view-columns` read one table each and stay.

## Measurement for the lazy-block decision

One trivial dynamic page under `(app)`, built twice in the Next.js example, differing only in its
import (`bsb` from `server.ts`, which composes all of `blocks.generated.ts`, against `bsbShell`
from `server-shell.ts`). Server chunks loaded at start, summed as the server baseline does:

| Page       | Raw       | Gzip    | Brotli  |
| ---------- | --------- | ------- | ------- |
| full `bsb` | 2,816,390 | 844,313 | 700,109 |
| `bsbShell` | 1,656,174 | 519,258 | 441,250 |
| Block set  | 1,160,216 | 325,055 | 258,859 |

The block set costs 325 KB gzip on a page that calls nothing, over three times the 100 KB bar
and almost all of the 334 KB between the floor (519 KB) and the median (853 KB) of ADR 0605. It
also explains `/beta`: its chain reaches `@/flags`, which imports `server-shell`, so it loads the
519 KB set, while the pages that import a feature module with `server.ts` load about 845 KB.

## Not done

Lazy block loaders are not built. The bar is met, but a `lazyBlock(() => import(...), manifest)`
needs more than a loader:

- `buildBlocks` calls each block's `provides` functions with the real client to build ports
  (`files`, `notifier`, `attachments`, `workflows`) and reads `events.types`, `schemas`, `options`
  and `composes` from the definition, so the manifest would carry all of them and the ports would
  have to be lazy too.
- A block client is a synchronous object with methods, sub-clients and wiring (route handlers,
  sinks, jobs, signers). An async proxy can serve the verbs `describe()` lists and must refuse the
  wiring until the block is loaded.
- `withBlockHooks`, `extendBlock`, `renameBlock`, `.with()` and `.using()` wrap the client.

That is a design of its own with tests per block family, and a half-built version would change
every server route. The route-level cut that exists (ADR 0542, named block sets) already removes
the whole 325 KB for a route whose blocks are in a set: moving the 172 files that import
`server.ts` onto the narrowest set that covers them is the cheaper next step, and `gen
serverBlocks` can produce the sets.

## Consequences

The type bench no longer reports a mapper cost that is not there, and its `centrakit` and `real`
baselines are higher in files mode by the enriched type, which is the real program. The next type
work is the `EnrichDatabase` cost under `createClient<Database>` (about four times the plain
type), not the mapper. An owned-column edit renders only the modules of the edited table.
