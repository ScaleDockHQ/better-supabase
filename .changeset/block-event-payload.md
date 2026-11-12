---
"better-supabase": minor
---

`blocks.<name>.events` takes `{ payload: { "<event type>": { <payload key>: "<column>" } } }`, which adds columns of the event's row to the payload the module writes to the outbox. An app that keeps its own columns on a block's table, such as a `customer_id` on `tasks`, no longer has to write a second `task.created` with them. Rendering fails for an event type the module doesn't record and for an event the module writes without a row. The tasks block passes its row to every event. `events: true` and `events: false` keep working.
