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
- `pnpm supabase:diff <name>`: a migration from the changes in `supabase/schemas` (pg-delta).
- `pnpm db:gen`: regenerate the typed client in every example and validation project.
- `pnpm typecheck:matrix`: published types against TypeScript 6 and 7 (5.9 has no Temporal lib).
- `pnpm size`: gzip size baselines per entry, min+gzip baselines for three app-shaped consumers (`CONSUMERS` in `tests/bundle/bundle.test.ts`), and the WinterTC import check.
- `pnpm test:integration`: integration suite against the running stack; it loads `SUPABASE_URL` and `SUPABASE_DB_URL` from `.env.development.local`.
- `pnpm --filter @better-supabase/example-nextjs test:e2e`: resets the local stack, builds the Next.js example with the testing API and runs its `instant()` specs (local only; see `docs/agents/nextjs.md`).
- `pnpm typecheck:perf`: type-instantiation benchmark on a 150-table schema and a 250-table schema with composite foreign keys (`centrakit`), on TypeScript 6 and 7; fails on >10% growth in instantiations or types, or when check time or the cold, warm or incremental `gen` time doubles (`update` rewrites the baseline).
- `pnpm --filter better-supabase bench`: runtime benchmarks for Server Component islands, `connect()` and `findMany` with 0, 3 and 6 plugins, `compilePostgrest`, codec decoding and list queries, and `server.context()` latency; each fails on a loose ratio, not an absolute time.
- `tests/validation-*`: six validation projects, run with `pnpm test`: code from two production apps ported to better-supabase (`crm` and `request-context`), CentraKit's schema adopting every SaaS SQL module (`centrakit`), a monorepo layout whose domain packages type their repositories from one runtime package (`monorepo`), the five apps on the docs Presets pages installed and driven end to end against the local stack (`recipes`), and every named preset installed as one migration with its generated `lib/blocks.ts` typechecked (`presets`; `gen` rewrites the wiring). `recipes` and `presets` are also part of `pnpm test:integration`.
- `pnpm --filter marketing test:e2e`: builds the marketing site and runs its Playwright smoke test of `/create` (local only).
- `pnpm version-packages`: the root `CHANGELOG.md` section, `changeset version`, then `scripts/sync-versions.ts` (the `VERSION` constant, plugin manifests and `server.json`). The release workflow runs it.

## Local development

`pnpm dev:portless` serves each app on a stable HTTPS URL through Portless
(`portless.json`). The first run asks to trust the Portless certificate
authority.

| App             | URL                           |
| --------------- | ----------------------------- |
| Marketing       | `https://www.localhost`       |
| Docs            | `https://docs.localhost/docs` |
| Next.js example | `https://example.localhost`   |

The seed (`supabase/seed.sql`) creates two Acme users with the password
`password123`: `admin@acme.test` (role `admin`) and `member@acme.test` (role
`member`).
