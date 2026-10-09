---
"better-supabase": minor
---

`better-supabase/mcp/sdk` serves MCP servers built on the official SDK (`@modelcontextprotocol/server` 2.3 or later, an optional peer), and `createMcp` works on hosted Edge Functions.

- `createMcpAuth(betterSupabase, { resource })` verifies Supabase tokens locally as an `OAuthTokenVerifier`, serves the RFC 9728 metadata and answers 401 and 403 challenges. `withBetterSupabaseMcp(server, auth)` gives every tool callback `db`, `auth` and `bs`.
- On Edge Functions the `resource` comes from the function slug. Both servers answer CORS preflights (`allowedOrigins`) and take `requiredRoles` and `waitUntil`.
