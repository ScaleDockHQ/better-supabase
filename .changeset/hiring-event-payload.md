---
"better-supabase": minor
---

The hiring block passes its application row to its events, so `blocks.hiring.events.payload` can add row columns to `application.created`, `application.hired`, `application.rejected`, `application.retracted`, `scorecard.submitted` and `interview.scheduled`, and job columns to `job_opening.opened` and `job_opening.closed`. A payload value can also be `{ sql }`, an expression that reads the row as `{row}`, for a value from a joined table such as the job title.
