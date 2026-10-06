---
"better-supabase": minor
---

Blocks that answer HTTP requests take a `problem` option that rewrites their error bodies into the app's own format (`createIdempotency`, `createInbox`, `createIncomingWebhooks`, `rateLimited`, and the `drainRoute`, `deliverRoute` and `relayRoute` options). `problemResponse` takes the same function as `format`. The function gets the RFC 9457 Problem Details and the `DbError`; the status and the `Retry-After` and `WWW-Authenticate` headers stay as they are. New types: `ProblemFormat` and `BlockProblemOptions`.
