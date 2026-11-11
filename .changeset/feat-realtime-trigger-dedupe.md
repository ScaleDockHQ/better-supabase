---
"better-supabase": minor
---

`database.realtime.triggers` and a topic's `broadcast` entries take `dedupe: "transaction"`, which sends each topic, event and payload once per transaction, so a bulk write or an audit log filled row by row sends one message per key instead of one per row. `dedupeKey` names the payload fields that tell messages apart. `upgrade` writes the trigger with `better_supabase.broadcast_once()`, and the function itself, into the `realtime.policies` output. It keeps the hashes in a transaction-local setting, so a commit or rollback clears them and a rolled-back transaction sends nothing.
