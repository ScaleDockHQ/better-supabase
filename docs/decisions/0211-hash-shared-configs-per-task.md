# 0211: Hash shared configs per task

- Status: accepted
- Date: 2026-11-03

## Context

`globalDependencies` hashed `pnpm-workspace.yaml`, `oxlint.config.ts`,
`oxfmt.config.ts`, `tsconfig.json` and `packages/typescript-config/**` into
every task. In 90 days `pnpm-workspace.yaml` changed in 113 commits and
`oxlint.config.ts` in 27, and each one missed the cache for every task and,
with `affectedUsingTaskInputs`, selected every task under `--affected`. The
root `package.json` depends on `@better-supabase/typescript-config`, so Turbo
already hashes that package in the global hash. The three `unit` shards ran
`turbo run test -- --shard=N/3`; passthrough arguments enter every task hash,
so each shard missed the cache for `better-supabase#build`.

## Decision

- `turbo.json` has no `globalDependencies`. The `lint` task reads
  `$TURBO_ROOT$/oxlint.config.ts`, and `//#lint:root` and
  `//#typecheck:tooling` list `tsconfig.json`. Root tasks already hash the
  whole repository, so `oxfmt.config.ts` needs no entry.
- `pnpm-workspace.yaml` is not an input. The lockfile changed in 101 of its 113
  commits, and Turbo hashes each package's slice of it. After a settings-only
  edit (`allowBuilds`, `publicHoistPattern`, `nodeOptions`), rerun with `--force`.
- The `unit` job runs `turbo run build` without passthrough arguments, then
  `turbo run test --only -- --shard=N/3`.
- Schema URLs point at `v2-11-10`, and root tasks carry a `description`.

## Alternatives considered

- `globalConfiguration`: `eslint-plugin-turbo` 2.11.10 reads only the top-level
  `globalEnv` and `globalPassThroughEnv`, so `turbo/no-undeclared-env-vars`
  would flag every variable once they move under `global`. Adopt it when the
  plugin reads `global.*`.
- Keeping `pnpm-workspace.yaml` global: every edit misses the cache everywhere.

## Consequences

One full cache miss on the first run after merge. A new shared root config
goes in the `inputs` of the tasks that read it.
