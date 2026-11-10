# 0638: Shard unit tests by duration, and skip CI work a push did not change

- Status: accepted
- Date: 2026-11-10

## Context

On a cache miss, one library unit shard took 16 minutes because Vitest
splits files by a hash of the path, and the slow SQL files landed together.
`tests/sql` was 87% of the unit time. A push to `main` always started the
seven Integration jobs and a full Release verify, even when the library and
`supabase/` had not changed. `static` ran doctor twice: once as a cached
Turbo task, then again to write SARIF. The Next.js example was built by
`verify / test` and by `Adapter build (Next.js)` at the same time, so both
missed the Turbo cache.

## Decision

- The unit project uses a sequencer that packs `--shard` by the durations in
  `packages/better-supabase/tests/unit-durations.json`. Unknown files take
  the median. `verify.yml` runs six shards. The coverage job prints the 20
  slowest files. `scripts/unit-durations.ts` rewrites the duration file from
  a Vitest JSON report.
- The three slowest files are split so each file stays under about a minute:
  the over-app module cases, the golden SQL renders, and the per-table
  adoption cases.
- The unit job logs `availableParallelism()` and leaves Vitest's worker
  count at one per core. The public GitHub runners already have 4 vCPUs.
- `ci.yml` runs the affected job on push against `github.event.before`. A
  missing base, or one that is not an ancestor, marks every output affected.
  Integration runs only when that output says so. The docs build runs on
  pull requests when the docs package changed, and not on push, because
  Vercel production builds the docs. The Vite example builds only when it
  changed.
- Release verify uses `--affected` against the last `main` commit whose
  Release run succeeded, when that commit is an ancestor. Otherwise it runs
  the full verify.
- `doctor:sarif` is a Turbo task with the same inputs as `doctor`, and
  `static` uploads the file it restores. It does not run doctor a second
  time outside the cache.
- Database CI is two jobs, Schema and Runtime, each with its own stack.

## Alternatives considered

- Reusing one booted `liteStack` for every test in a file. A local run of
  `tests/sql/modules/leave-over-app.test.ts` took 59s for 17 tests, and the
  test bodies were about 52s of that, so the boot is not the time. The files
  that call `liteStack` are 44 of the 66 minutes of `tests/sql`. Removing the
  boot would not make that directory 40% faster. Each test also passes its
  own check as seed SQL, so a shared database would need a clone after
  migrate and before seed. A wrong clone would hide failures.
- Merging pgTAP into an Integration shard. The two jobs would become one
  job of about 12 minutes.
- A larger runner. The runners already have 4 vCPUs, and the time is in
  single-worker files and uncached work, not in waiting for a runner.

## Consequences

Branch protection must require `verify / unit (1/6)` through `(6/6)` instead
of `(1/3)` through `(3/3)`, and `Schema` and `Runtime` instead of the single
Database job. `tests/unit-durations.json` is an input of the test task, so a
stale file still runs every test: it only unbalances the shards. Refresh it
with `scripts/unit-durations.ts` when the coverage summary shows a file far
above its recorded duration. A push that does not change the library skips
Integration and, in Release, the unit shards.
