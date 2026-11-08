# 0451: Ship the server-imports codemod and the server gates, and record why the rest of the layout waits

- Status: accepted
- Date: 2026-11-08
- Amends: 0393, 0450

## Context

ADR 0393 deferred the generated layout (`schema.ts`, `tables/`, per-instance block
modules) and ADR 0450 deferred the codemod for moved server imports, single-function
block verbs, `ServerContext<App>`, per-instance server modules and permissions in the
bootstrap RPC. ADRs 0262 to 0265 already ship one module per table, the block config
slices, `AppDb` and the client barrel check (doctor BS621). This record closes what
can be closed and states, with measurements, why the remainder stays open.

## Decision

### Shipped

- `better-supabase codemod server-imports` splits each import from
  `better-supabase/server` so the account, CSV and rate-limit helpers import from
  `server/accounts`, `server/csv` and `server/rate-limit`. An aliased or type-only
  import keeps its form, and an import that moved nothing is untouched.
- `tests/next-build` holds the server chunks of every page and route handler to
  `server-baseline.json`. It sums the `R.c("server/chunks/...")` entries of each
  `page.js` and `route.js` in raw, gzip and brotli, and fails when one grows. The
  update lowers a number and never raises it. On the Next.js example: the customers
  page loads 3,329,424 B raw (797,505 B brotli), the login page 2,610,787 B
  (625,564 B), the `/api/customers` route 2,324,540 B (574,395 B).
- `tests/types/perf` measures a server program (`createServer` over the generated
  schema, a context per request, 40 tables read through `ctx.db`) next to the client
  program. Default profile, TypeScript 7: 38,842 instantiations and 17,036 types.
  CentraKit profile: 42,966 and 23,288. Both have a baseline with the 10% gate.

### Not done, with the reason

- **A cold-start gate.** A route module cannot be loaded outside Next.js: requiring
  `page.js` throws `AsyncLocalStorage accessed in runtime where it is not
  available` before any app code runs. Starting `next start` per route needs the
  local stack, and compiling the chunks with `vm.Script` measures V8, not the app.
  The byte gate above is the deterministic part, and the cold-start time stays
  with the Playwright budget tests.
- **`MaxDepth` 4 in `renameBlock`.** The renamed client nests client, method, result,
  row and nested row, and a change record adds the `field` key below that. At 4,
  `tests/blocks/rename-block.test-d.ts` fails two cases, and at 5 it fails the
  "renames the column a change names" case. The cap stays at 6.
- **`nullable`, `hasDefault` and `description` in the `.d.ts` only.** The runtime reads
  `nullable` (`core/repository.ts`, `core/table-schema.ts` decoding) and the testing
  generator reads `hasDefault`. Across all 19 table modules of the example, `hasDefault`
  is 1,045 B and `description` 473 B of 27,874 B, and a page ships one table, so the
  saving is under 100 B per page against a behavior change in `better-supabase/testing`.
- **Derived `Insert` and `Update`.** Measured and reverted in ADR 0265.
- **`import type` everywhere.** Generated files already use inline `type` specifiers,
  which TypeScript erases under `verbatimModuleSyntax`; no import loads a type at runtime.
- **The file names `schema.ts` and `blocks/index.ts`.** Renaming the default output
  from `generated.ts` touches about 530 references (fixtures, examples, docs, goldens)
  and changes no byte a page ships. It waits for a release that already breaks
  generated imports.
- **Per-instance `blocks/<instance>.ts` modules, a lazy `app.ts` and one block builder per
  db.** ADR 0263 measured per-instance client modules: app routes grew 1.6 KB. On the
  server a route that imports `betterSupabase` composes every instance through
  `defineBlocks`, because a block's consumed ports need their providers. Modules per
  instance only help once `defineBlocks` can build a subset db whose type and ports are
  checked, which is a change to `DbOf`, the port resolution and every adapter.
- **`ServerContext<App>` and `BetterNext<App>`.** `ServerContext` appears in 18 source
  files and `BetterNext` in 3, across the 12 adapters; replacing the 7 and 9 parameter
  forms is a breaking type change that needs its own matrix run on TypeScript 6, 7 and 7.1.
- **Multi-table block verbs as single SQL functions.** Each verb is repository calls
  with plugin hooks and event handlers between steps (invariant 5), and ADR 0234's
  `server.transaction` already makes them atomic. Moving them into SQL changes where
  events fire in about a hundred blocks.
- **Permissions in the bootstrap RPC.** The sessions wrapper cannot name
  `better_supabase.my_permissions`: permissions come from the app's
  `AuthorizationProvider` (invariant 15), and the permissions block is only one provider.
  The authorizer's `load` keeps its one call per request.

## Consequences

Moving to the new server entries is one command. Server regressions fail `pnpm verify`
by bytes per route and by type cost. The deferred items stay visible here and in the
changeset.
