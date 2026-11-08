---
"better-supabase": minor
---

`approvalWaiter.create(token)` registers the approval hook up front and returns a handle to `wait` on later, so a wake between steps is not lost. `resumeStreamResponse` takes `sse` (answers as `text/event-stream`) and `transform` (pipes the chunks through a `TransformStream`). `problem429` takes `{ extra, headers, format }` to add members to the 429 body.
