---
"better-supabase": minor
---

`audit_event` and `audit_event_trusted` take `support_session`, `impersonated_by` and `impersonation_reason`, stored ahead of the values in the caller's `act` claim. The service role may pass any values; another caller only itself as `impersonated_by`, from a token without an `act` claim. `sql sync` drops the previous signatures. Module actions pass them through `ModuleAudit.supportSession`, `impersonatedBy` and `impersonationReason`, so the `support-sessions` module's `support.started` and `support.ended` entries now carry the session id, the admin and the reason in the impersonation columns instead of only in metadata. `AuditEventInput` gains `supportSessionId`, `impersonatedBy` and `impersonationReason`, and `auditEventOf` fills them for `support.*` events from `sessionId`, `adminId` and `reason`.
