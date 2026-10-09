---
"better-supabase": minor
---

The outbox (`better-supabase/blocks/outbox`) hands consumers the raw rows and moves failing events aside. Run `better-supabase sql upgrade`.

- `outbox.consume(consumer, handler)` passes `OutboxEvent` rows (`OutboxHandler`), and `relayRoute` accepts such a handler.
- A failing consumer backs off (`maxBackoff`), and after `maxAttempts` failures an event moves to `outbox.deadLetters(consumer)`. `purge` takes `{ ignoreIdle }`, and `createOutbox` takes a `BlockTransport`.
