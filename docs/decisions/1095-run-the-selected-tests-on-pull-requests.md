# 1095: Run the selected tests on pull requests and the whole suite on main

- Status: accepted
- Date: 2026-11-20

Supersedes the sharding parts of [0638](0638-shard-unit-tests-and-skip-unchanged-ci.md), the pull
request half of [0686](0686-ci-runs-the-full-gate.md) and [1092](1092-shard-the-pgtap-suite.md).

## Context

A pull request waited for the longest of four unit shards (490 to 801 seconds), a coverage run
(106 seconds), a static job (p95 859 seconds) and the Schema job (560 to 917 seconds). Each job
spent 70 to 95 seconds installing before it ran anything. The doctor ran twice, the scale pgTAP
files made the Schema job swing by minutes, and a one-line docs change still started most of them.

## Decision

- `ci.yml` starts with an install-free `changes` job. `verify.yml` splits `static` into parallel
  lanes, runs the heavy checks as a matrix, and runs one `unit` job on `vars.UNIT_RUNNER` (falling
  back to `ubuntu-latest`) instead of shards plus a coverage job.
- A pull request runs the library tests `scripts/select-tests.ts` picks from the diff: the files
  that import a changed file, directly or through each other, the owner rules for generated and
  shared inputs, and the whole suite when it cannot tell. `main` and `workflow_dispatch` run the
  whole suite with coverage. A red `main` opens the `main-red` issue so a missed failure surfaces
  within one merge.
- The doctor runs once. The scale pgTAP files and the type-time gates move to `nightly.yml` and
  `database-scale.yml`. `database.yml` is one Schema job again.
- Pruned tests: variant golden families became property assertions, 17 single-case over-app
  module tests and the help snapshot went, and tests that cannot fail were deleted.
  `scripts/check-test-budget.ts` stops the library tests growing past `scripts/test-budget.json`.
- Every job has a `timeout-minutes` near its new p95, and `pnpm ci:baseline` prints the numbers.

## Alternatives considered

- Reusing one booted PGlite stack or a per-worker migrated copy (0638): a stack is about 1 second
  of boot and 0.2 seconds of DDL replay, so a copy saves under 25% of a stack and risks a clone
  that hides a failure. Measured again on 2026-11-20, not adopted.
- Packing shards by cached durations: the shard job itself is gone, so there is nothing to pack.
- Keeping the string-only module tests: they pin option behavior the default golden does not
  render, so they stay.
- Always running everything on pull requests: it kept the 14 minute critical path.

## Consequences

A pull request is red or green in the time of its slowest selected lane. A change that the import
graph misses reaches `main` and is caught there, so a maintainer fixes it from the issue. The
selector's scanner tests and `LOCAL_SELECTION_CAP` keep local `pnpm check` honest. Revisit if
`main-red` opens more than once a month.

Maintainer steps: create a larger runner (8 or 16 vCPU) in a runner group that allows this
repository, set the repository variable `UNIT_RUNNER` to its label, and set a spending limit.
