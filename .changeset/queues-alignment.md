---
"better-supabase": minor
---

Run jobs that Vercel Queues pushes to a route. `vercelQueueRoute(jobs, { client, handlers })` from `better-supabase/blocks/queue` wraps the `@vercel/queue` client's `handleCallback`: it checks each payload against the queue's schema, runs the handler with the same tenant context as `drain`, retries a failed delivery after `retryAfter` and acknowledges the one that reaches `maxAttempts`. `vercelQueueNodeRoute` does the same for `(req, res)` frameworks over `handleNodeCallback`. `jobs.runJob(queue, delivery, handler)` runs one pushed job for other push backends.

`vercelQueueProvider` now accepts a `QueueClient`, which only sends (its `read` rejects), and sets `retentionSeconds` on a delayed message so a delay longer than a day is kept until it runs. Delays past 7 days throw, since Vercel Queues keeps a message at most that long. The `onReceive` option reports each `receive` result, with the reason a poll found nothing.
