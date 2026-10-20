---
"better-supabase": minor
---

Realtime topic triggers read less and send less.

- A generated trigger function reads each parent row once per changed row, into a local record, however many values, payload keys and topics use it. A custom payload is built once for all topics. Before, every lookup ran again for the payload, for each topic's values and for each nested level. Run `sql sync` to rewrite the functions; the messages they send don't change.
- `topic.trigger(table, { when: { changed: ["status"] } })`, and `when` on a `realtime.triggers` entry, send an update only when one of the listed columns changed. On a trigger for updates alone it becomes the trigger's `when` clause, otherwise an early return in the function. Inserts and deletes always send.
- A delete whose lookup finds no parent row, such as a child removed by `on delete cascade`, raises a warning that starts with `better-supabase: realtime lookup found no row` instead of skipping the topic silently. The Realtime docs have a new "Deletes and cascades" section.
