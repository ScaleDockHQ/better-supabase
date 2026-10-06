---
"better-supabase": minor
---

`outbox.consume(consumer, handler)` claims and acknowledges like `relay`, but hands the handler the outbox rows (`OutboxEvent`, with `actorId`, `tenant` and `key`) instead of CloudEvents, for consumers inside the app that need the actor. `relayRoute` accepts such a handler in place of a sink. New type: `OutboxHandler`.
