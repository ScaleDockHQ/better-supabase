---
"better-supabase": patch
---

`audit_event` works in a read-only support or impersonation session again, so the session's actions are audited with the session and impersonator from its `act` claim.
