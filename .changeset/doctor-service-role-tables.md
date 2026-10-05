---
"better-supabase": minor
---

`tables.<name>.serviceRole: true` marks a table that only `service_role` reaches. Its models are still generated for admin clients, and doctor (BS106) no longer reports it as missing a Data API grant; instead it reports any grant `anon` or `authenticated` still has on it. BS107 skips server-only tables. Before, the only way to silence BS106 for such a table was `exclude`, which also dropped it from the generated types.
