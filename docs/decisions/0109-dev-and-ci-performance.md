# 0109: Keep hooks, CI and Next.js builds fast

- Status: accepted
- Date: 2026-10-26

## Context

A docs-only commit took 7.2s in the hooks, and a push after a library change
took 109s because pre-push ran the tests. In CI, `verify / test` took 754s, of
which 692s was the library's unit run with coverage, and one integration shard
took 291s because the pg-delta round trip is a single 117s file. Any edit in
`packages/better-supabase` missed the Turbo cache for every task: the root
`package.json` depended on the workspace package, and Turbo hashes the root's
workspace dependencies into the global hash. `CI` and `NODE_ENV` were hashed,
so CI, Vercel and laptops never shared a cache entry. The docs build
prerendered all 1,435 pages on every pull request. Worktrees started without
dependencies or env files, and `portless run --force` let one worktree kill
another's dev server.

## Decision

- Turbo: the root depends on no workspace package; root scripts and workflows
  run the CLI by path or as `pnpm better-supabase`. Task `inputs` skip tests,
  markdown and configs a task doesn't read. `CI` and `NODE_ENV` pass through
  unhashed; an env var is hashed only by the tasks whose output it changes.
  `lint` depends on `^build`, because oxlint reads the library's `dist`.
- Hooks: pre-commit runs `ultracite fix` on the staged files and pre-push runs
  `pnpm gate`, an affected `lint lint:root typecheck` against `origin/main`
  that reads the remote cache without writing it. Tests run in CI only.
- Vitest: the library runs on half the cores locally. In `verify.yml` its unit
  run is three `unit` shards with blob reports; a `coverage` job merges them
  and checks the thresholds, which a shard on its own skips. Integration keeps
  three shards plus a pg-delta job; CentraKit gets its own validation job.
  Only `verify`'s static job on the default branch saves the pnpm store.
- Next.js: `@better-supabase/next-config` sets `BSB_BUILD_SCOPE` to `full` for
  a Vercel production build and `minimal` everywhere else, and
  `scopeStaticParams` keeps 3 entries per dynamic route in `minimal`.
  GitHub Actions builds skip prerender source maps and the Turbopack build
  cache, which they never restore. The docs job logs peak memory.
- Worktrees: `scripts/worktree-setup.ts` (from `.cursor/worktrees.json`)
  installs offline and copies env files without the main stack's keys;
  `--db` starts the worktree's own stack. `dev:portless` drops `--force`, and
  `env:local` writes the worktree's prefixed Portless URLs.
  `pnpm supabase:prune` lists stacks unless given `--apply`.

## Alternatives considered

- Tests in pre-push: they made a push take as long as CI's slowest job, and
  CI runs them anyway.
- A shared `vitest.shared.ts`: each workspace config sets different projects,
  and the only shared settings were two lines, so the shard override lives in
  the library config.
- Vitest sharding by duration: Vitest shards by file count, so the slow
  pg-delta file gets its own job instead.
- `turbopackSeedCacheFromWorktree`: seeded from another branch's cache, the
  docs build failed with 217 missing MDX modules.
- `turbopackGc`: a warm rebuild took 17.6s against 15.8s, with the same cache
  size.
- `turbopackLazyDynamicImports`: the first dev request took 10.5s off and
  10.6s on; docs has two dynamic imports.
- A minimal build scope only when `CI` is set: Vercel previews set `CI` too,
  and their full prerender is the slowest build left.

## Consequences

A docs-only commit takes about 4.2s in the hooks. A push no longer runs tests,
so a failing test shows up in CI. Library edits hit the cache for unrelated
tasks. Pull request CI and Vercel previews no longer prerender every docs and
marketing page; a page outside the first three of its route renders on its
first request. Set `BSB_BUILD_SCOPE=full` to check every page before a
release. Branch protection must require `verify / unit (1/3)`, `(2/3)`,
`(3/3)`, `verify / coverage`, `Integration (pg-delta round trip)` and
`Integration (CentraKit)`. Revisit the shards when the library's unit run
grows past about 120s per shard, and the build scope if a route regresses
only in its prerender.
