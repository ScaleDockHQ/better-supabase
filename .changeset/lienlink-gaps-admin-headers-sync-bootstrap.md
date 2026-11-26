---
"better-supabase": minor
---

Closes gaps an adopter had worked around:

- The audit log records a service write for a member (`admin(context, { as })`, the `x-bsb-actor` header) with `actor_kind = 'user'` instead of `service`; `actor_role` keeps `service_role`. Run `better-supabase upgrade` and diff to pick up the audit functions.
- `server.admin(context, { as, headers })` sends `headers` on every request too, such as the request id and client address the audit log reads.
- `bsb.bootstrap({ redirect, require: "user" })` also redirects a caller without a user session, with `?reason=signed_out` (`reasons.signedOut`), and types the result as an active user session.
- `syncWithAuth(db, auth, { connectOptions })` passes `connectOptions` to every `connect`, such as PowerSync's `{ checkpointMode: "requests" }`.
- `createUploadConnector({ onUploaded })` gets each batch's changes after `complete()` succeeds, without the upload waiting for it. `CrudEntryLike` carries `previousValues`.
- `createClient`, `bindClient` and `createNativeClient` take `verifySession: { rpc, schema? }`: a session that signs in or loads from storage is checked against the sessions block's `bootstrap_<rpc>` wrapper, and signed out locally when the server ended it.
