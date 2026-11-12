# 0686: CI runs the full gate; locally agents run `pnpm check`

- Status: accepted
- Date: 2026-11-12
- Amends: 0108, 0109

## Context

An audit of 30 days of agent sessions found that `pnpm verify` ran 1,991 times in 203 sessions
with a median of 161 seconds, a cache hit ratio of 0, and 69% failures. A library edit makes
`turbo --affected` select 119 tasks in 40 packages, and the library unit suite alone runs 1,825
files. CI returns the same answer in a median of 399 seconds on its own cores. The local hooks ran
`pnpm gate` on commit and on push, which is that same selection. Agents also slept 84,802 seconds
polling `gh` for CI.

## Decision

- `pnpm check` (`scripts/check-changed.ts`) is the local gate. It takes the files changed against
  `origin/main` (or the files you pass) and runs the format check, Oxlint, the workspace typecheck
  and the tests that mirror or import the files. A file imported by more than three modules runs
  its mirror test only; CI runs the rest.
- The old `pnpm check` (`ultracite check` on the whole repo) is now `pnpm check:format`.
- `pnpm verify` is the full gate and runs in CI. Run it locally only when you need a full result.
- Lefthook runs `ultracite fix` on staged files and `pnpm check` on commit and on push, each job
  with a time limit.
- The library `test` script no longer collects coverage. `test:coverage` does, and the CI unit
  shards pass `--coverage`, so the thresholds are enforced in CI only.
- `pnpm ci:wait` waits for the pull request checks and prints one line per failed job.
- `@arethetypeswrong/cli` is removed. `check:publish` runs `publint` only. This also drops
  TypeScript 5.6 and the `supports-hyperlinks` override of 0634 from the install.

## Alternatives considered

- Keep `pnpm verify` before every push: the measured cost and failure rate were the problem.
- Cache the hooks harder: the selection is the cost, and a cache hit ratio of 0 says the inputs
  change on every edit.
- Keep attw and run it with `pnpm dlx`: it still pulls TypeScript 5.6 on every release job, and
  `publint` already checks the exports map.

## Consequences

A coverage drop or a failure outside the changed files shows up in CI, and the follow-up is a
second push. The packed tarball's types are no longer checked under the `esm-only` attw profile;
the `tests/types` projects compile consumers against the built package. Revisit when CI failures
that a local `pnpm verify` would have caught pass 30% of pushes.
