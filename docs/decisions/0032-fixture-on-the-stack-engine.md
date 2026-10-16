# 0032: Run the fixture on the Supabase CLI's stack engine

- Status: accepted
- Date: 2026-10-16

## Context

The fixture stack in `supabase/` ran on Docker with fixed ports (API on
55421, Postgres on 55422). Every worktree and agent shared those ports, so
only one checkout could run a stack at a time, and CI installed a second copy
of the CLI through `supabase/setup-cli` next to the one in the catalog. ADR
0006 kept the CLI's native stack opt-in because its Realtime failed the
private-channel integration tests on CLI 2.119.0.

The stack engine in CLI 2.121.0 (`[experimental] stack = true`) starts
services on first request, picks ports per checkout or worktree, and runs on
a native, Docker or Podman runtime. On the native runtime the fixture starts
in about 6 seconds with its migrations and seed, and pgTAP, `db lint`,
`db advisors`, the drift check, the validation suites and all but three
integration tests pass. The three that fail (two in
`realtime.integration.test.ts`, one in `access-policies.integration.test.ts`)
fail the same way on the engine's Docker runtime: Realtime denies a private
channel join that the legacy Docker stack allows.

## Decision

`supabase/config.toml` sets `[experimental] stack = true` and sets no port
keys, so each checkout and branch gets its own stack. `pnpm supabase:start`
creates it on the native runtime (`--runtime native`), then runs
`pnpm env:local`, which writes the stack's URLs, keys and runtime
(`SUPABASE_RUNTIME`) from `supabase status --env --output-format json` to
`.env.development.local`. `pnpm test:integration` and `pnpm db:gen` load that
file, and the suites read `SUPABASE_URL` and `SUPABASE_DB_URL` instead of
fixed ports: the integration project throws when they are missing, and the
validation projects skip as they do when the stack is down.

CI and `database.yml` run the catalog's CLI (`pnpm exec supabase`) through
`.github/actions/supabase-stack`, which starts the stack with
`--runtime native`, caches the downloaded service binaries per CLI version
and exports the `SUPABASE_*` variables. The three failing tests skip when
`SUPABASE_RUNTIME` names a stack engine runtime, and a separate CI job runs
both suites on the legacy engine (`SUPABASE_EXPERIMENTAL_STACK=0`).

`databaseUrl()` in the CLI reads `DB_URL` from `supabase status` when nothing
configures the database and `config.toml` sets no `[db] port`, so `gen`,
`doctor`, `seed` and `snapshot` work on any app that turns the engine on.

## Alternatives considered

- Keep Docker with fixed ports: one stack per machine, and CI keeps paying
  for Docker image pulls.
- Turn on the engine but keep fixed ports: worktrees and agents still
  collide on one stack.
- Fall back to Docker in CI until Realtime passes: the stack engine's Docker
  runtime fails the same three tests, so only the legacy engine would help,
  and the faster native start would wait on an upstream fix.

## Consequences

Agents and worktrees run stacks side by side, CI needs no Docker for the
main integration job, and the CLI version lives in one catalog pin. Ports
change per checkout, so nothing may hardcode them; run `pnpm env:local`
after starting a stack in a new worktree. The stack engine is experimental,
so a CLI bump can change its behavior; run the full flow before bumping.
When a CLI release passes the three Realtime tests on the stack engine,
remove the `stackEngine` skips and the legacy CI job.
