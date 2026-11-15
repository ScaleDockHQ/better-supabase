---
"better-supabase": minor
---

Breaking: `scores` gets `archiveModel` and `restoreModel`, and the hard delete
of a model is `purge`, behind its own `permissions.purge` key (it falls back to
`scores.manage`). An archived model leaves `models`, `list` and `top`, and
`compute` and `saveModel` refuse it with `SCORES_MODEL_ARCHIVED`; its versions
and every score stay, and `history` still reads them. `models` takes
`includeArchived`, and `ScoreModel` carries `archivedAt`.

| Before                                 | After                                |
| -------------------------------------- | ------------------------------------ |
| `scores.deleteModel(id)`               | `scores.purgeModel(id)`              |
| `delete_score_model(model_id)`         | `purge_score_model(model_id)`        |
| event `score_model.deleted`            | event `score_model.purged`           |
| `hooks.deleteModel`                    | `hooks.purgeModel`                   |
| `list_score_models` with two arguments | a third argument, `include_archived` |

New events are `score_model.archived` and `score_model.restored`. Run
`better-supabase upgrade` and apply the migration. See the 0.66 to 0.67 guide.
