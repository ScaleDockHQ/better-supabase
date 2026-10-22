---
"better-supabase": minor
---

Add the `scores` block: tenant-editable scoring models that write versioned scores to any record.

- `better-supabase add scores` installs score models per organization. A model has rules (a rules filter tree worth points), metrics (a number field or the vote score times a weight, with a cap) and bands. Saving changed rules, metrics or bands raises the model's version and keeps the old definition.
- `createScores` from `better-supabase/blocks/scores` saves models, computes a record's score from its fields with a breakdown, and reads current scores, history and the top scores per band. A changed score emits `score.changed`, and `scoresSection` shows a record's scores on its page. Lead scoring and health scoring are models (ADR 0067).
- New permissions: `scores.read`, `scores.manage` and `scores.compute`.
