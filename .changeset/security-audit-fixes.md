---
"better-supabase": patch
---

Security fixes for the usage and waitlist modules, auth and full-text search.

- `within_quota` returns false for a caller who is not a member of the tenant, so a signed-in user can no longer probe another tenant's remaining quota with it. Policies that members of the tenant run keep working.
- `usage_status` and `usage_overview` (`usage.current` and `usage.overview`) need `usage.read`, like the usage tables and `usage_history`. Before, any member could read them, including the default `member` and `viewer` roles. Run `better-supabase sql sync` to update the functions.
- `join_waitlist` (`waitlist.join`) no longer tells a signed-out or signed-in caller whether an address was approved or already signed up. It always returns `status: "waiting"`, and for an entry that left the line, the place a new address would get. The service role still sees the real status.
- The verified-token memo for an inline JWKS object is keyed by the audience and issuer too. Before, a token that one server accepted without an `audience` check was accepted by a second server that shared the same JWKS object and required an audience.
- A `search` filter checks its `config` against the shape of a text search configuration name (`english`, `pg_catalog.dutch`) and returns an `invalid_request` error otherwise. Before, a crafted config inside an `OR` added filter terms to the PostgREST query.
