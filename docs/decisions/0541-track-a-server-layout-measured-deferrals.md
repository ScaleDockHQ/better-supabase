# 0541: Record what the server layout items measured and why four stay open

- Status: accepted; the A1 and A2 findings are superseded by 0542
- Date: 2026-11-08
- Amends: 0451, 0393

## Context

ADR 0451 deferred per-instance server modules, a lazy `app.ts`, `ServerContext<App>`
and `BetterNext<App>`, single-function block verbs, a cold-start gate and the file
renames, each with a reason but without the number a build would give. This record
measures them on the Next.js example (`tests/next-build/server-baseline.json`: the
customers page 3,329,424 B raw, the login page 2,610,787 B, `/api/customers`
2,324,540 B) and the type bench (`tests/types/perf`), and keeps only what the
numbers support.

## Decision

### Measured and shipped

- **`MaxDepth` 4.** ADR 0540.

### Measured and not shipped

- **`ServerContext<App>` and `BetterNext<App>`.** A pilot gave `ServerContext` one
  `ServerApp<M, F, E, C, P, B, D>` parameter and rewrote its 23 uses in 17 source
  files and 2 type tests. It typechecked after one export. The server program of
  the type bench moved the wrong way: TypeScript 7, default profile, 38,842 to
  38,850 instantiations and 17,036 to 17,051 types; CentraKit profile 42,966 to
  42,974 and 23,288 to 23,303; TypeScript 6 default 38,693 to 38,701. The
  parameters were never the cost: the `Db` over the schema is. A breaking type
  change that costs 8 instantiations is reverted, and `BetterNext<App>` (3 files,
  the same parameter list) is not piloted.
- **Per-instance server modules and a lazy `app.ts` (A1, A2).** _Superseded by ADR 0542: the pilot cut the three routes by 48 to 54 percent, because the estimate below charged block code to shared library chunks._ The customers
  `[id]` page loads one 2.14 MB minified chunk shared by the app routes. By source
  map, `better-supabase/dist/blocks` is 254 KB of it (12%), the rest of the
  library 838 KB, npm packages 532 KB and the app 517 KB (the env schema and its
  validator alone 217 KB). A subset `defineBlocks` could remove at most that
  254 KB block share from a page, 7.5% of its 3.38 MB, and only for blocks no
  consumed port needs. `defineBlocks` already takes any block map; what a subset
  lacks is a generated module per instance, a `DbOf` that follows the subset and
  a port check that names the missing provider. That is the design ADR 0263
  measured at +1.6 KB per app route on the client side, so it needs the server
  numbers of a working generator, not an estimate, and it is not started here.
- **Single-function verbs (A5).** `decide_approval_items`, `approve` and `reject`
  are already one SQL function each, so approval decisions have no round trips to
  remove (`decideForSubject` is a list and a decision). `tags.replace` makes one
  read plus one call per changed tag: 1 + 3 + 2 = 6 transport calls for three
  attaches and two detaches, pinned in `tests/blocks/tags/tags.test.ts`. A SQL
  function would make that 1 call, and would also stop `replace` from running the
  `attach` and `detach` hooks per tag, which the tags client documents ("Helpers
  call the hooked client, so app hooks see each step"). The saving is real only
  for large tag sets, and the cost is a changed hook contract, a new SQL function
  with its pgTAP test, a regenerated snapshot, fixtures and catalogs, and a data
  contract change in every installed app. Not widened beyond the measurement.
- **Cold-start gate (A7).** ADR 0451's reasons hold: a route's `page.js` throws
  outside Next.js, and `next start` per route needs the stack. The byte gate stays
  the deterministic check.
- **File renames and `.d.ts`-only metadata (A8).** No codemod exists for the 530
  references, and ADR 0451 measured under 100 B per page for the metadata. Nothing
  ships a byte less, so nothing changes.

## Consequences

This record moves no baseline. ADR 0542 moves the three routes after measuring what this
record estimated. What stays open here is the `tags.replace` function (a hook contract
decision, decided against in ADR 0542), `ServerContext<App>` (reverted on a measured loss)
and a cold-start gate (needs the stack in CI). Each has its number here.
