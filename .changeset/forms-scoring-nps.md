---
"better-supabase": minor
---

The `forms` block scores quizzes and rolls up Net Promoter Scores. Existing forms keep working: scoring and NPS only apply to versions that use them.

- A field takes a `correct` answer and `points` (1 by default), and a definition takes `scoring.passMark`, a percentage. `publish` moves the correct answers into the new `form_answer_keys` table, which no client role reads, so respondents never see them; callers with `forms.manage` get them merged back.
- Postgres scores a final submission inside `submit` and stores `score`, `max_score` and `passed` on `form_submissions`. Submissions return them as `score: { score, maxScore, passed }`, and the `form_submission.submitted` event carries them. `formScore(definition, answers)` computes the same grade in the app.
- The `nps` field type takes an integer from 0 to 10. `forms.nps(formId, { field, since, until, bucket })` (SQL `form_nps`) returns the promoters, passives, detractors and score, overall and per UTC day, week, month, quarter or year. `npsCategory` and `npsScore` do the same in the app.
- On adopted tables, map `tables.answerKeys` and the `score`, `maxScore` and `passed` submission columns to score; without them, `publish` refuses a correct answer with `FORM_SCORING_UNAVAILABLE`.

The forms module moves to version 2. Run `better-supabase sql sync`, then `db diff`, to add the table and columns.
