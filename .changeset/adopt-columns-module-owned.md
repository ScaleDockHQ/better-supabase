---
"better-supabase": patch
---

`sql sync` and `sql upgrade` no longer refuse an adopted table for a column the module adds or does not read. The outbox's `xid` column, which adopt mode adds itself, no longer has to be declared first, and an adopted `webhooks-out` secrets table needs only the column of its `secretStorage`: `vault_secret_id` with Vault (the default), or `secret` with `"column"`, without mapping the other to `null`.
