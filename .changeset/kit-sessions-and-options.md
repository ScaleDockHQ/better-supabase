---
"better-supabase": minor
---

The new `sessions` SQL module adds `better_supabase.session_active()` for restrictive policies: it is false once the token's session was revoked or expired, or the user is banned or deleted.

Options that only exist to match an existing schema are accepted in `mode: "adopt"` only: `tokenStorage: "plain"` for invitations, `secretStorage: "column"` and non-`text` `eventIdType` or `runIdType` for webhooks-out, and `kitSource` or `defaultSource` for the outbox. Doctor BS314 warns about each until you remove it. `better-supabase/sql` exports `migrationOptionUses(kits)` to list them. The `assignmentCeiling` and `triggerPrefix` options, the invitations `errorCodes` option and `kits.access.disabled.tenantKey` are removed.
