---
"better-supabase": minor
---

Vercel Queues: `vercelQueueProvider` takes `retention`, `headers` and a `consumerGroup` function per queue, hashes idempotency keys longer than 256 characters, and its `stats` points to the Vercel dashboard. New `vercelQueueTriggers` writes the `vercel.json` triggers for a push route, `vercelSendOptionsOf`, `vercelIdempotencyKey` and `vercelTopicOf` expose the send rules, and `withDeadLetters` hands jobs past their last attempt to a sink.
