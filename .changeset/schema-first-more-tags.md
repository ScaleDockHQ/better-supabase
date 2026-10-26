---
"better-supabase": minor
---

`gen` now also reads the `json`, `encrypted` and `events` table tags, and `migrate schema-first` writes them. `json meta=Type` types a jsonb column (`meta=import:module#Name` imports the type), `encrypted ssn=bigint` marks a sealed column, and `events on="created, updated"` lists the outbox events. A config key still wins over a tag.
