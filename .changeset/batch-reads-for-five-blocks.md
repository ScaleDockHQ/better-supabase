---
"better-supabase": minor
---

Five block clients read many rows in one call, so a page no longer sends one request per row. Run `better-supabase upgrade` and apply the new migration to add the functions.

| Block        | New method                               | Replaces a loop of        |
| ------------ | ---------------------------------------- | ------------------------- |
| `ai-chat`    | `runs.steps.listFor({ runIds, limit })`  | `runs.steps.list(runId)`  |
| `versions`   | `getMany(ids)`                           | `get(id)`                 |
| `hiring`     | `applicationsForJobs({ jobIds, state })` | `applications({ jobId })` |
| `templates`  | `getMany(ids)`                           | `get(id)`                 |
| `care-plans` | `getMany(planIds)`                       | `get(planId)`             |

Results keep the order of the ids you pass. An id that is missing or that the caller cannot read has no entry instead of failing the batch.
