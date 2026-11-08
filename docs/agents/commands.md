# Commands

`AGENTS.md` lists the everyday commands; this is every root script and
what it checks.

- `pnpm install`: install (pnpm 12, Node 24).
- `pnpm verify`: the gate before every push. It runs the format check, lint
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
- `pnpm supabase:start`, `pnpm supabase:reset` and `pnpm supabase:test`: the local stack on the CLI's stack engine (native runtime, ports per checkout and branch, URLs written to `.env.development.local`), a reset from the migrations and seed, and the pgTAP tests.
- `pnpm supabase:prune`: list the running stacks of branches merged into `main`, in this checkout and its worktrees; `--apply` stops them and keeps their data. macOS runs out of shared memory segments after about 30 running stacks.
- `pnpm check:migration-order`: fails when the branch adds a migration that sorts before the newest one on `origin/main` (`MIGRATION_BASE` names another base).
- `pnpm check:app-architecture`: fails when the Next.js example app breaks the feature-sliced RSC rules of ADR 0310 (a page imports a `*-queries` file or awaits `params`, a feature takes `params`, a file prefix differs from its folder, an async component has no `Skeleton`); `node scripts/check-app-architecture.ts --print` lists the findings for `scripts/app-architecture-allow.json`.
- `pnpm check:naming`: fails when a renamed name returns or code breaks a rule of `packages/better-supabase/api/naming.json`; `node scripts/check-naming.ts --print` lists the current violations for the allowlist.
- `pnpm test:scripts`: the tests of the repo scripts in `scripts/`.
- `pnpm supabase:diff <name>`: a migration from the changes in `supabase/schemas` (pg-delta).
- `pnpm db:gen`: regenerate the typed client in every example and validation project.
- `pnpm typecheck:matrix`: published types against TypeScript 6 and 7 (5.9 has no Temporal lib).
- `pnpm size`: gzip size baselines per entry, min+gzip baselines for three app-shaped consumers (`CONSUMERS` in `tests/bundle/bundle.test.ts`), and the WinterTC import check.
- `pnpm test:integration`: integration suite against the running stack; it loads `SUPABASE_URL` and `SUPABASE_DB_URL` from `.env.development.local`.
- `pnpm --filter @better-supabase/next-build test`: builds nothing itself; it waits for the Next.js example's `build` (Turbo `dependsOn`) and holds the First Load JS of every route (minified, gzip, brotli) to `tests/next-build/baseline.json`. A route never grows; `update` (`NEXT_BUILD_UPDATE=1`) lowers a number or adds a route and fails on growth.
- `pnpm typecheck:perf`: type-instantiation benchmark on a 150-table schema and a 250-table schema with composite foreign keys (`centrakit`), on TypeScript 6 and 7; fails on >10% growth in instantiations or types, or when check time or the cold, warm or incremental `gen` time doubles (`update` rewrites the baseline). It also times `upgrade` on a copy of the CentraKit fixture (cold, warm no-op, one app-file edit) and fails when a count of rendered or written files grows; `update` scales the seconds to the baseline machine by hand.
- `pnpm --filter better-supabase bench`: runtime benchmarks for Server Component islands, `connect()` and `findMany` with 0, 3 and 6 plugins, `compilePostgrest`, codec decoding and list queries, and `server.context()` latency; each fails on a loose ratio, not an absolute time.
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

The seed (`supabase/seed.sql`) creates two Acme users with the password
`password123`: `admin@acme.test` (role `admin`) and `member@acme.test` (role
`member`).
