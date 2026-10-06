---
"better-supabase": minor
---

`realtime.policies: { from, output }` writes the `realtime.messages` policies of every topic the `from` modules export (`defineTopic`) to a schema file on `better-supabase sql sync`, and `sql sync --check` fails when that file is stale, so topic policies get a writer and a drift check like the SQL modules.
