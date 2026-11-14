---
"better-supabase": minor
---

Record the admin behind an impersonated call on block events. While a support
session runs, every block event and row mutation event carries `impersonatedBy`
(the admin) next to `actorId` (the impersonated user), `blockCloudEvent` puts it
in `data.impersonatedBy`, and `auditSink` writes it as the audit entry's
`impersonatedBy`. Nothing changes for calls outside a session.
