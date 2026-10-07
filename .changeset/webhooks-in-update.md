---
"better-supabase": minor
---

`createIncomingWebhooks().update(id, { name, metadata, verify, signatureHeader })` and the `update_incoming_webhook` SQL function rename an endpoint, rebind it through `metadata` or change its verification mode without changing its token. A new signing mode returns its secret once and deletes the old Vault secret. The `update` permission key gates it.
