---
"better-supabase": minor
---

**Behaviour change:** the audit log now records a service write made for a member (`admin(context, { as })`, the `x-bsb-actor` header) with `actor_kind = 'user'`, where it recorded `service`; `actor_role` keeps `service_role`. A filter or report that read such writes as `service` needs `actor_role` instead. Run `better-supabase upgrade` and diff to pick up the audit functions.

- `server.admin(context, { as, headers })` sends `headers` on every request too, such as the request id and client address the audit log reads.
- `bsb.bootstrap({ redirect, require: "user" })` also redirects a caller without a user session, with `?reason=signed_out` (`reasons.signedOut`), and types the result as `UserBootstrap`, an active user session. `require` without `redirect` is a type error and throws.
- `syncWithAuth(db, auth, { connectOptions })` passes `connectOptions` to every `connect`, such as PowerSync's `{ checkpointMode: "requests" }`.
- `createUploadConnector({ onUploaded })` gets each batch's changes after `complete()` succeeds, without the upload waiting for it. `CrudEntryLike` carries `previousValues`.
- `createClient`, `bindClient` and `createNativeClient` take `verifySession: { rpc, schema? }`: a session that signs in or loads from storage is checked against the sessions block's `bootstrap_<rpc>` wrapper (in the schema `gen` recorded, else `better_supabase`), and signed out locally when the server ended it and the same user is still signed in.
