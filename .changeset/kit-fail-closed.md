---
"better-supabase": minor
---

Breaking: the SQL kit fails closed. `current_tenant_id()` returns a tenant only while the caller is a member, the claim is cleared when a member is removed, and `kits.access.activeTenant` defaults to `'resolver'` (the tenant `ServerOptions.tenant` resolved, then the claim). Disabled organizations deny access, the `permdock` and `custom` access models need an assignment rule, and only an owner can transfer ownership. A member can never raise their own role or assign one above it.

Platform invitations move to `platform_invitations` under a role ceiling that accept checks again, accept checks that the inviter can still assign the role, and `valid_for` is capped by `maxValidFor`. Support sessions refuse platform targets and writes by default and allow one active session per admin; a token with an `act` claim has no platform permissions.

Doctor BS312 reports a kit schema listed in `[api] schemas`. `set_actor` keeps `created_by` on updates, `track_realtime` refuses a table without the tenant column, the rate limit and `request_ip()` use the right-most forwarded hop, audit is append-only by default, idempotency keys are scoped to the caller, public buckets get no select policy, members see only public profile columns, and outgoing webhooks follow no redirects, cap the response body and use 32-byte secrets.
