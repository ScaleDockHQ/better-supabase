---
"better-supabase": patch
---

`createMcp` and `createMcpAuth` work on hosted Supabase Edge Functions without a `resource` option. When `SUPABASE_FUNCTION_SLUG` or `SB_EXECUTION_ID` is set, the advertised `resource` is the public `<origin>/functions/v1/<slug>` (from `SUPABASE_PUBLIC_URL` or the gateway's `X-Forwarded-*` headers), the 401 and 403 challenges point to `<resource>/oauth-protected-resource`, which the gateway routes to the function, and the authorization server is Auth on the same origin. `allowedHosts` reads `X-Forwarded-Host` there. Both servers also serve the metadata at that suffix route everywhere, and answer CORS preflights with the MCP headers so browser clients can connect (`allowedOrigins` limits the echoed origin, `cors: false` turns it off).
