---
'better-supabase': minor
---

Add MFA assurance levels. User sessions expose `aal` and `amr`; route, action,
Hono, oRPC, edge and MCP guards take `aal: 'aal2'` and answer `403` with
`code: 'INSUFFICIENT_AAL'` and `required`; `requireAal` redirects pages in the
proxy; `checkAal`, `aalOf` and `amrOf` are exported from `better-supabase/server`.
The new `mfa` SQL kit module adds `better_supabase.mfa_satisfied()` for
restrictive policies, and doctor reports policies that read `auth.mfa_factors`
directly as BS108.
