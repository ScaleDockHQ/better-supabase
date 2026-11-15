---
"better-supabase": minor
---

The queue block can read one message back: `queue.enqueueJob(input)` returns `{ jobId: "queue:<queue>:<id>" }`, `queue.get({ queue, id })` returns its run record (state, attempts, last error, never the payload), and `queue.runs` is the `queue` kind of `createJobs`. The new `get_job(queue, job_id)` SQL function (queue module version 16) backs it; run `better-supabase upgrade` and apply the migration. `enqueue` keeps returning the numeric id.
