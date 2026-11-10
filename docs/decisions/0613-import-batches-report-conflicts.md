# 0613: Import batches report conflicts and finish on the counts

- Status: accepted
- Date: 2026-11-10

## Context

`finish_import_run` treated a run as `completed_with_issues` when the counts
text contained `"conflicted":`. `mergeCounts` always writes that key, including
when the count is 0, so every run with counts finished with issues.
`import_apply_batch` returned only the `conflicted` count. The conflicting
keys were rows in `import_run_issues`.

## Decision

The outcome checks that some entity's `conflicted` count is greater than 0.
`mergeCounts` always writes that key, so a text search for `"conflicted":`
treated every run with counts as completed with issues. The conflicting keys
are `conflictKeys` on the batch result (ADR 0610).

Set-based classification of unchanged rows stays on the per-item loop. ADR 0441
measured that classification at a fraction of a millisecond per item, and the
search key casts (ADR 0616) were the cost a batch target could not remove.

## Consequences

A run with no conflicts and no errors can finish `completed`. Callers can read
the conflicting keys from the batch result without listing issues.
