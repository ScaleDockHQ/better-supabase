---
"better-supabase": patch
---

`ctx.supabase.auth.oauth.listGrants()` and `revokeGrant({ clientId })` work on a request context (`bsb.context()` in Next.js, Hono and the other adapters). The context client holds the caller's access token but no Auth session, so supabase-js answered both with `AuthSessionMissingError`; they now send the token to Supabase Auth's `/user/oauth/grants` and return the same `{ data, error }` shape.
