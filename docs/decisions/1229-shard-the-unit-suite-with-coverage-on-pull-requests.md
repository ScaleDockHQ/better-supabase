# 1229: Shard the unit suite with coverage on pull requests and main

- Status: accepted
- Date: 2026-11-24

Supersedes the unit test parts of [1095](1095-run-the-selected-tests-on-pull-requests.md).

## Context

[1095](1095-run-the-selected-tests-on-pull-requests.md) moved the library's unit tests to one
job on a larger runner (`vars.UNIT_RUNNER`). That runner was never created, so the job ran on the
4 vCPU `ubuntu-latest`. Measured over 810 CI and 301 Release runs (2026-11-14 to 2026-11-24):

- The whole suite (2092 files, 27445 tests, about 96 minutes of summed file time, the 200 slowest
  files about 88% of it, mostly `tests/sql/**`) took 42 to 55 minutes on `main`. The selected
  tests on a pull request took 26 to 30 minutes at p50 and 47 at p90, because most diffs widen to
  most of the suite.
- Pull requests ran raw Vitest, so `main` never reused their work, and coverage gated only on
  `main`: 18 of 26 failed Release unit jobs failed on coverage after the pull request was green.
- `static (generated)` took 6.5 minutes at p50: the Next.js example's `gen:check` and doctor
  shared four cores for about 4 and 3.5 minutes each.

## Decision

- `verify.yml` runs the unit suite as 18 `unit (n/18)` jobs on `ubuntu-latest`, on pull requests
  and on `main`. The Turbo `test` task gets `--shard`, `--reporter=blob` and `--coverage`, and keeps
  `.vitest/blob/**` as its output. A custom sequencer in `packages/better-supabase/vitest.config.ts`
  packs files longest-first onto the lightest shard by the durations in
  `packages/better-supabase/tests/unit-durations.json`, and runs each shard's slowest file first.
  The longest file takes about 2.3 minutes, so more shards would not shorten the slowest one.
- The `coverage` job merges the blob reports and checks the same thresholds on the same scope, so
  a pull request fails on coverage before it merges. A shard checks none.
- The same job fails when a file runs 50% and 5 seconds over its baseline, or a test takes over
  half the 60 second timeout, and writes the 20 slowest files to the step summary
  (`scripts/unit-durations.ts`). `docs/agents/tooling.md` says how to refresh the baseline.
- `main` reuses a pull request's shards through the Turbo Remote Cache when the merge commit has
  the same inputs as the pull request's merge ref, which holds when `main` did not move between
  the last CI run and the merge.
- `static (generated)` splits into `generated` (`gen:check`), `doctor` and `type matrix` lanes.
  Integration runs in four shards instead of three. Every job's `timeout-minutes` is about twice
  its p90. The `full` input and the `UNIT_RUNNER` expression are gone.
- `scripts/select-tests.ts` stays for `pnpm check`; CI no longer uses it.

## Alternatives considered

- Keeping the selected tests on pull requests next to the shards: a selection cannot check
  coverage, and the sharded whole suite finishes sooner than the selection did on one runner.
- A larger runner: it costs money and a repository setting, and one 16 vCPU machine still
  queues the slowest files behind each other.
- Vitest's own `--shard`: it splits by path hash, so one shard can draw several of the two minute
  `tests/sql` files.

## Consequences

A pull request's critical path is the slowest shard plus the coverage merge, instead of 26 to 47
minutes. Each run uses more runner minutes for setup (about 1.2 minutes per job), which is free on
a public repository. A new slow file runs as the median until the baseline is refreshed. Revisit
the shard count when the longest shard passes 5 minutes, or when the summed file time changes by
more than a quarter.
