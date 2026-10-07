---
"better-supabase": minor
---

Incoming webhook endpoints join `data-lifecycle` exports and purges: an organization export includes them without the token hash, the secrets or their Vault ids, and the purge deletes them with their Vault secrets. `options.tables` entries and module lifecycle declarations take `omit`, a list of columns left out of export files, and `data_lifecycle_tables()` returns it as a sixth `omit` column, so a data-lifecycle module in custom mode needs it.
