---
"better-supabase": patch
---

Fix `db.$search` (and `$many`, `$stats`) going missing on the server when a module that only defines a list query loads the lean client runtime after the full one. A lean install no longer replaces an installed full runtime, so `db.$search is not a function` no longer fails pages that mix `better-supabase/list` over the client app with a server `db`.
