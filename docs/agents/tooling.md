# Tooling

## Registry and versions

- Query the registry with `pnpm view <pkg> version` or `pnpm view <pkg> time --json`.
  Don't read `~/.npmrc` or other credential files.
- `minimumReleaseAge` in `pnpm-workspace.yaml` rejects a release younger than
  a day. Pin the previous release and move on; never lower the setting.
- Catalog entries are exact versions. A package the root uses goes into the
  catalog and into the root `devDependencies` as `catalog:`. The named
  catalogs `deps` and `peers` hold the ranges `better-supabase` publishes for
  its runtime dependencies and peers; use them there instead of `catalog:`, so
  apps don't get a second copy of a package they already have.

## TypeScript 7.1 upgrade checklist

The repo stays on TypeScript 7.0.2 until a 7.1 release and a matching
`oxlint-tsgolint` build both pass `minimumReleaseAge`. The bump is one
commit series:

1. Move `typescript` in the default catalog and the two `peerDependencyRules`
   entries (`jsonv-ts>typescript`, `@sveltejs/kit>typescript`) together.
2. Move `oxlint-tsgolint` to its 7.1 build in the same commit; tsgolint
   embeds the compiler and refuses a mismatched one.
3. Run `pnpm typecheck`. 7.1 rejects a distributed conditional branch that
   passes `T` to a generic constrained on the original `T`
   (`'B' is only assignable to the non-distributed 'A'`). The library had no
   such case when audited in October 2026; the generated
   `database.types.ts` helpers (`Tables`, `TablesInsert`, `Enums`) are the
   likely place, and they are fixed by regenerating with a newer
   `@supabase/postgrest-typegen`, never by hand.
4. Refresh the baselines: `pnpm --filter ./tests/types/perf update`, `pnpm size` and the
   CLI startup entry, with the before and after numbers in the commit.
5. Decide separately whether `base.json` moves to `es2026`: runtime support
   on every WinterTC target decides it (invariant 6), not the compiler.
6. Consider bringing back `fumadocs-typescript` hover types once its API
   for the native compiler is stable.

## Scripts and hooks

- `pnpm verify` is the gate. `pnpm check` runs `ultracite check`, the Oxfmt
  check and Oxlint across the repo, and never replaces it.
- `pnpm fix` runs `ultracite fix`: Oxfmt and the Oxlint autofixes. The
  root `oxlint.config.ts` holds every rule; workspace configs extend it.
- Lefthook runs `ultracite fix` on staged files and lints on commit, runs commitlint on the
  message, and runs `turbo run lint lint:root typecheck test --affected` on push.
- Commit headers stay under 73 characters and body lines under 101.

## Tests and coverage

- Coverage counts every file in `packages/better-supabase/src` (except
  `src/cli/bin.ts`), from unit tests only, with a separate threshold set for
  `src/cli/**`. Code that needs a database or the
  network gets a fake from `tests/fixtures` (`fake-sql`, `fake-pg-pool`,
  `fake-fetch`, `fake-storage`, `fake-connect`) or an injectable seam with a
  default, such as `connect(url, load)` or `createPostgres({ pool })`.
- The package's `test` script runs only the `unit` project, so a running
  local stack does not add integration coverage that CI never sees. Check
  coverage with `pnpm --filter better-supabase test`, not a bare
  `vitest run --coverage`.
- `thresholds.autoUpdate` rewrites `vitest.config.ts` when coverage grows
  (not in CI). Commit that change; never lower a threshold to make a run pass.
- Vitest caches results in `node_modules/.vitest-cache` at the repo root. When
  a run reports failures for code you have already fixed, delete that folder.
- `tests/types/perf` gates check time against a calibration program it
  checks first, so the baseline holds on machines of any speed. A check-time
  failure in CI is a real slowdown, not a slow runner.
- The CLI tests read the library's fixtures through
  `tests/cli/fixtures/library.ts`. The CLI imports the library only through
  its entry files (`src/sql/index.ts`, not `src/sql/registry.ts` or `src/sql/render.ts`), which the CLI
  build turns back into `better-supabase/*` imports.
- `tests/standards` holds one conformance test per adopted standard. Tests
  that have an official JSON Schema validate against a vendored copy in
  `tests/standards/schemas`; `sources.test.ts` fails when a file's SHA-256
  differs from `SOURCES.md`. Ajv needs two adjustments, both noted there:
  the draft-04 SARIF schema has its `id` renamed to `$id`, and the OpenAPI
  schemas have `$dynamicRef` rewritten to a static `$ref`.
- The `index.ts` of storage, jobs, mcp, list, next, realtime, config, query,
  react and webhooks only re-exports; `tests/entries.test.ts` enforces it.
  Put code in a sibling module.

## Changesets and releases

- `pnpm version-packages` runs `scripts/root-changelog.ts` before
  `changeset version`, because `changeset version` deletes the changeset
  files the root changelog is built from.
- The release workflow opens the version PR with `pnpm run version-packages`
  and publishes with `pnpm run release` when `NPM_PUBLISH` is set.

## CI

- The composite action in `.github/actions/setup` connects the Vercel Remote
  Cache through OIDC (the job needs `id-token: write`), then installs Node and
  pnpm with the store cache. Composite actions can't read the `vars` context,
  so pass values in as inputs.
- `verify.yml` is a reusable workflow with a `fail-fast: false` matrix. Add a
  check there as a new matrix entry, not as a new workflow.
- A new `verify` step is a Turbo task: a workspace script, or a root script
  registered as `//#<name>` in `turbo.json`, with `inputs` that list every
  file it reads (`$TURBO_ROOT$/...` for files outside the workspace). Add it
  to the `turbo run` in the root `verify` script and to `verify.yml`. A step
  that times itself (`typecheck:perf`) runs in its own `turbo run`, after
  the parallel one.
- Turbo fails `lint` when code reads an env var that no `turbo.json` declares
  (`turbo/no-undeclared-env-vars`). Declare it in `globalEnv` or the task's `env`.
  Keep the top-level `global*` keys: the rule does not read a `global` block.
- `lint`, `typecheck` and `test` depend on `transit`, not `^build`. Workspace
  imports resolve to `src` through the `@better-supabase/source` export
  condition (tsconfig `customConditions`, Vitest `resolve.conditions`), and
  `publishConfig.exports` is the map that ships. A task that reads `dist`,
  such as the CLI's `bin.test.ts` or `tests/bundle`, declares `^build` in its
  workspace `turbo.json`. Add a new export to both maps;
  `tests/entries.test.ts` checks that they match.
- Turbo signs remote cache artifacts (`remoteCache.signature`). CI reads the
  key from `TURBO_REMOTE_CACHE_SIGNATURE_KEY` (at least 32 bytes); without it,
  local runs warn and use only the local cache.
- A `.vercel` link at the repo root (from `vercel link` or `vercel env pull`)
  makes `withEve` read the root `vercel.json`, whose services have no eve
  service, so `next typegen` in `apps/examples/eve` fails the `lint` task with
  `vercel.json already defines services`. CI has no link. Locally, set the
  folder aside outside the repo for the run (`mv .vercel /tmp/bs-vercel`; a
  renamed folder in the repo is no longer gitignored) and put it back after.
