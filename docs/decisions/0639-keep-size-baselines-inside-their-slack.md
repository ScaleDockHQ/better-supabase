# 0639: Keep a size baseline until the measurement leaves its slack

- Status: accepted
- Date: 2026-11-10

## Context

`tests/bundle/baseline.json` was rewritten in hundreds of commits, and the
Next.js route baselines, the practice counts and the coverage thresholds
moved with them. `update` stored the exact new byte count of every entry,
including ones that had moved by less than the slack the check already
allows. Two pull requests then conflicted on those lines. A practice count
that fell also failed until the baseline file was committed again.

## Decision

A committed number is a ceiling. The check fails when a measurement grows
past the slack around it. `update` rewrites a number only when the
measurement leaves that slack: it rises past it, or it falls by more than
it. A movement inside the slack keeps the number already in the file.
Practice counts and the static DDL counts fail only when they grow. A lower
count does not need a new file. `UPDATE_PRACTICES=1` still tightens the
ceiling when someone wants the drop recorded. Coverage thresholds stay as
written in `vitest.config.ts`. A local run no longer raises them.

## Alternatives considered

- Deleting the baselines. The check is what stops a route or an entry from
  growing without anyone looking. The conflict came from rewriting numbers
  the check did not use.
- Rounding every number up to a coarse ceiling in one commit. That rewrites
  the files once, and the same keep-inside-slack rule avoids that churn
  without a new scale.

## Consequences

A pull request conflicts on a baseline when it moves the same entry past
the slack, not when gzip noise moves a neighbouring entry. Refresh a
baseline with the existing `update` command after an intended change.
