# Commands

`AGENTS.md` lists the everyday commands; this is every root script and
what it checks.

- `pnpm install`: install (pnpm 12, Node 24).
- `pnpm check`: lint, typecheck and the mirrored tests of the changed workspaces (`node scripts/check-changed.ts`; related tests only when a file has at most 3 importers). About 7 s on one library file. Hooks run it.
- `pnpm check:format`: the old `ultracite check`. `pnpm --filter better-supabase test:coverage`: unit tests with coverage (CI). `pnpm ci:wait`: watch the PR checks and print failed jobs.
- `pnpm verify`: the full gate, run by CI (ADR 0686); run it locally only to reproduce a failure. It runs the format check, lint
  (type-aware Oxlint on the Ultracite presets in the root `oxlint.config.ts`), the prose check, the PermDock name check, typecheck,
  Knip, Turbo boundaries, tests, doctor and `pnpm audit`. Every step except
  the format check, boundaries and audit is a cached Turbo task with
  `inputs` in `turbo.json`, so a second run only repeats what changed.
- `pnpm fix`: `ultracite fix`, Oxfmt and the Oxlint autofixes.
- `pnpm format`, `pnpm lint`, `pnpm typecheck`, `pnpm knip` and `pnpm boundaries` run one step of `verify`.
- `pnpm build`: tsdown build of every package and app.
- `pnpm test`: unit and type tests (vitest, `expectTypeOf`). Tests live in each
  workspace's `tests/` folder, and the root `vitest.config.ts` lists the projects.
  Each published package's unit tests alone must hold the coverage thresholds
  in its `vitest.config.ts` (never below 90% lines, statements and functions,
  80% branches); `autoUpdate` raises them locally, never in CI.
- `pnpm dev:portless`: docs, marketing and the Next.js example on HTTPS
  `.localhost` URLs (see Local development).
- `pnpm supabase:start`, `pnpm supabase:reset` and `pnpm supabase:test`: the local stack on the CLI's stack engine (native runtime, ports per checkout and branch, URLs written to `.env.development.local`), a reset from the migrations and seed, and the pgTAP tests. Run `pnpm supabase:reset:library` before `pnpm supabase:test`: the pgTAP files create their own fixtures, and the example rows of `seeds/example.sql` and `seeds/finance-demo.sql` reuse their ids and names (51 files fail on the full seed, none on the library seed, as in CI).
- `pnpm supabase:start` checks the macOS shared memory cap (24 of 32 segments) before it starts and names the fix. `pnpm supabase:prune --segments` prints the count; `--destroy` (with `--apply`) deletes the stacks of merged branches and of missing checkouts, data included.
- `pnpm supabase:prune`: list the running stacks of branches merged into `main`, in this checkout and its worktrees; `--apply` stops them and keeps their data. macOS runs out of shared memory segments after about 30 running stacks.
- `pnpm check:migration-order`: fails when the branch adds a migration that sorts before the newest one on `origin/main` (`MIGRATION_BASE` names another base).
- `pnpm check:app-architecture`: fails when the Next.js example app breaks the feature-sliced RSC rules of ADR 0310 (a page imports a `*-queries` file or awaits `params`, a feature takes `params`, a file prefix differs from its folder, an async component has no `Skeleton`); `node scripts/check-app-architecture.ts --print` lists the findings for `scripts/app-architecture-allow.json`.
- `pnpm check:example-coverage`: fails when a catalog block or preset has no entry in `apps/examples/nextjs/coverage/block-coverage.ts`, or when a listed route has no `page.tsx`; it prints how many blocks wait for their screen.
- `pnpm check:example-findings`: validates `docs/agents/example-findings.md` against the lanes in `docs/agents/block-consistency-audit.md`. It fails on a stray header, blank row or duplicate id in the report tables, on stale status counts at the top, on an unfinished row (open, partly fixed or deferred) that no lane's Findings line names, and on a lane that is `merged` while one of its rows is unfinished. `node scripts/check-example-findings.ts --write` rewrites the status counts.
- `pnpm example:perf-report`: prints one line per Next.js example route with the first load, server bundle, HTML payload, database budget and cold, warm and client timings from `apps/examples/nextjs/perf-results/example-perf`; `--scale <pgtap-output>` adds the `SCALE_MS` lines of a scale run and `--json` prints JSON.
- `pnpm db:seed:scale`: adds volume to the running local stack. Alone it writes 5,000,000 audit events and 1,000,000 notification recipients to Acme. `--tier smoke|m|l|xl` writes tenants, customers, notes and the append-only tables at that tier through the generators in `supabase/seeds/scale`, in import mode (`better_supabase.importing()`), so row triggers do not run: `m` is 60,000 customers over 150 organizations, `l` is 1,000 organizations with one holding 1,000,000 customers, notes, audit events and notification events, `xl` has 10,000,000 audit and notification rows. `--tenants <n>` sets the organizations, `--clean` removes the rows of an earlier tier first and `--dry-run` prints the batches.
- `pnpm check:naming`: fails when a renamed name returns or code breaks a rule of `packages/better-supabase/api/naming.json`; `node scripts/check-naming.ts --print` lists the current violations for the allowlist. It also fails when a block with SQL has no `supabase/tests/database/<block>*.test.sql`; blocks without one yet are in `scripts/pgtap-allowlist.json`, which only shrinks (EX-1351).
- `pnpm test:scripts`: the tests of the repo scripts in `scripts/`.
- `pnpm supabase:diff <name>`: a migration from the changes in `supabase/schemas` (pg-delta).
- `pnpm db:gen`: regenerate the typed client in every example and validation project.
- `pnpm typecheck:matrix`: published types against TypeScript 6 and 7 (5.9 has no Temporal lib).
- `pnpm size`: gzip size baselines per entry, min+gzip baselines for three app-shaped consumers (`CONSUMERS` in `tests/bundle/bundle.test.ts`), and the WinterTC import check. A size inside the 5% or 256 byte slack keeps its committed number, so `update` does not rewrite the file for noise.
- `pnpm test:integration`: integration suite against the running stack; it loads `SUPABASE_URL` and `SUPABASE_DB_URL` from `.env.development.local`.
- `pnpm --filter @better-supabase/next-build test`: builds nothing itself; it waits for the Next.js example's `build` (Turbo `dependsOn`) and holds the First Load JS of every route (minified, gzip, brotli) to `tests/next-build/baseline.json`. A route never grows past the slack. `update` (`NEXT_BUILD_UPDATE=1`) adds a route and lowers a number only when it falls by more than that slack.
- `pnpm typecheck:perf`: type-instantiation benchmark on a 150-table schema and a 250-table schema with composite foreign keys (`centrakit`), on TypeScript 6 and 7; fails on >10% growth in instantiations or types, or when check time or the cold, warm or incremental `gen` time (the `types` task only) doubles (`update` rewrites the baseline). The server program, a context with `ctx.db` over 120 tables, is gated the same way. It also times `upgrade` on a copy of the CentraKit fixture (cold, warm no-op, one app-file edit, one audited table, one column on an owned table) and `upgrade --check` (cold, warm, owned column), and fails when a count of rendered or written files grows; `update` scales the seconds to the baseline machine by hand. A `runtime` case times a chain of `AsyncResult` steps against a bare promise chain in microseconds and fails when the ratio grows by half (ADR 0581).
- `pnpm --filter better-supabase bench`: runtime benchmarks for Server Component islands, `connect()` and `findMany` with 0, 3 and 6 plugins, `compilePostgrest`, codec decoding and list queries, and `server.context()` latency; each fails on a loose ratio, not an absolute time.
- `pnpm --filter better-supabase bench:jwt`: the JWT matrix (1, 50, 150 and 500 memberships by 200 and 500 custom roles, with per-tenant overrides) against the running stack: hook parts with and without the hook plan, claim, token and cookie bytes, `tenant_ids_with`, and token verification cold and warm. It rolls back everything it inserts; `--json` prints the cells, and `tests/bench/baselines/jwt-matrix.json` holds the last recorded run (ADR 0523).
- `tests/validation-*`: twelve validation projects, run with `pnpm test`: code from two production apps ported to better-supabase (`crm` and `request-context`), CentraKit's schema adopting every SaaS SQL module (`centrakit`), an app that owns its tables in `supabase/schemas` and adopts three modules, held to an empty `supabase db schema declarative sync --strict-coverage` after `upgrade`, to a second `upgrade` that keeps every app object, and to doctor failing on the seeded ownership and coverage patterns (`declarative`), and the same checks on Lienlink's shape, where blocks own the `better_supabase` tables and app views project them with an `instead of` insert trigger, app ALTERs, an audit trigger, an `auth.users` trigger, a generated column and a composite foreign key (`lienlink`); both need the Supabase CLI and Docker for the shadow database, not a running stack), a monorepo layout whose domain packages type their repositories from one runtime package (`monorepo`), the five apps on the docs Presets pages installed and driven end to end against the local stack (`recipes`), every named preset installed as one migration with its generated `lib/blocks.ts` typechecked (`presets`; `gen` rewrites the wiring), and a generator and a framework binding written outside the library with only the public kit, run cached and on a worker thread and detected (`plugins`), `init --yes` in a new app for each framework and package manager, then `gen` from a snapshot and a typecheck with no edit (`new-app`), the `migrations` and `migra` workflows on the declarative fixture's tables, where `upgrade` writes one content-stamped migration after the newest (or the module files in `supabase/schemas`) and a second run changes nothing (`migrations`), and a B2C app whose modules write no tenant column, helper or policy (`single-tenant`; the three need no Supabase CLI or Docker). `recipes` and `presets` are also part of `pnpm test:integration`.
- `pnpm version-packages`: the root `CHANGELOG.md` section, `changeset version`, then `scripts/sync-versions.ts` (the `VERSION` constant, plugin manifests and `server.json`). The release workflow runs it.

## Local development

`pnpm dev:portless` serves each app on a stable HTTPS URL through Portless
(`portless.json`). The first run asks to trust the Portless certificate
authority.

| App             | URL                            |
| --------------- | ------------------------------ |
| Marketing       | `https://www.localhost`        |
| Docs            | `https://docs.localhost/docs`  |
| Next.js example | `https://example.localhost`    |
| eve example     | `https://eve.localhost`        |
| Vite example    | `https://vite-react.localhost` |

The seed (`supabase/seed.sql`, the library rows the pgTAP suite runs on; `supabase/seeds/example.sql` and `seeds/finance-demo.sql` add the example app's rows and the Schema job leaves them out) creates two Acme users with the password
`password123`: `admin@acme.test` (role `admin`) and `member@acme.test` (role
`member`).
