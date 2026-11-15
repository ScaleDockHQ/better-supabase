# 1053: Archive and restore a score model (lane Y2, slice 7)

- Status: accepted
- Date: 2026-11-15
- Amends: 1052

## Context

ADR 1052 gives the score model an archive. `delete_score_model` removes the
model with its saved versions and every score computed under it, and
`enabled = false` only stops new computations: a turned-off model still lists,
still shows its current scores and still accepts `save_score_model`. Nothing
hides the same rows an archive would.

## Decision

`archive_score_model` and `restore_score_model` need `scores.manage` and record
`score_model.archived` and `score_model.restored` once. Archiving an archived
model, or restoring one that is not archived, returns it unchanged.

- The models table gains an optional `archived_at` column, and the model JSON
  carries `archivedAt`.
- `list_score_models` hides archived models by default and takes
  `include_archived` as a third argument, so the migration drops the two
  argument form. `subject_scores` and `top_scores` leave an archived model's
  current scores out. `get_score_model` still reads one by id, and
  `score_history` still reads the scores computed under it.
- `compute_score` and `save_score_model` refuse an archived model with
  `SCORES_MODEL_ARCHIVED` (SQLSTATE 55000). Restoring the model keeps its
  `enabled` flag, so a model that was off stays off.
- `delete_score_model` becomes `purge_score_model` and `score_model.deleted`
  becomes `score_model.purged`. The purge permission is `permissions.purge`,
  falling back to `manage`, so no role migration is needed (ADR 0851).

## Consequences

Breaking for callers of `deleteModel`, for sinks that match
`score_model.deleted` and for `hooks.deleteModel`; the changeset and the 0.66 to
0.67 guide have the old-to-new table. A custom models table without
`archivedAt` gets neither function and keeps the two-argument list.
