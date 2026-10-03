# Tooling

## Registry and versions

- Query the registry with `pnpm view <pkg> version` or `pnpm view <pkg> time --json`.
  Don't read `~/.npmrc` or other credential files.
- `minimumReleaseAge` in `pnpm-workspace.yaml` rejects a release younger than
  a day. Pin the previous release and move on; never lower the setting.
- Catalog entries are exact versions. A package the root uses goes into the
  catalog and into the root `devDependencies` as `catalog:`.

## Scripts and hooks

- `pnpm verify` is the gate. There is no `pnpm check` script.
- Lefthook formats and lints staged files on commit, runs commitlint on the
  message, and runs `turbo run lint typecheck test --affected` on push.
- Commit headers stay under 73 characters and body lines under 101.

## Tests and coverage

- Coverage counts every file in `packages/better-supabase/src` (except
  `src/cli/bin.ts`), from unit tests only, with a separate threshold set for
  `src/cli/**`. Code that needs a database or the
  network gets a fake from `tests/fixtures` (`fake-sql`, `fake-pg-pool`,
  `fake-fetch`, `fake-storage`, `fake-connect`) or an injectable seam with a
  default, such as `connect(url, load)` or `createPostgres({ pool })`.
- `thresholds.autoUpdate` rewrites `vitest.config.ts` when coverage grows.
  Commit that change; never lower a threshold to make a run pass.
- The CLI tests read the library's fixtures through
  `tests/cli/fixtures/library.ts`. The CLI imports the library only through
  its entry files (`src/sql/index.ts`, not `src/sql/kit.ts`), which the CLI
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
