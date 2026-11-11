---
"better-supabase": minor
---

`topic.trigger()` and `database.realtime.triggers` take `dedupe: "transaction"`, which sends each topic, event and payload once per transaction, so a bulk write or an audit log filled row by row sends one message per key instead of one per row. `dedupeKey` names the payload fields that tell messages apart. The hashes live in a transaction-local setting, so a commit or rollback clears them and a rolled-back transaction sends nothing.
