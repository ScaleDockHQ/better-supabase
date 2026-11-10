---
"better-supabase": minor
---

`defineTopic` takes `broadcast`, a list of tables whose row changes the topic sends, and `better-supabase upgrade` writes their triggers next to the topic's policies in the `realtime.policies` file. `gen.types.also` lists more files that get a copy of `database.types.ts`, for apps in a monorepo that share the types; `gen --check` fails when a copy is stale.
