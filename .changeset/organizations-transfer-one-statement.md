---
"better-supabase": patch
---

`transfer_ownership` promotes the new owner and demotes the calling owner in one `update`, so a statement-level guard on the number of owners no longer refuses every transfer. It also refuses a new owner whose account is disabled, with `ORGANIZATION_FORBIDDEN`.
