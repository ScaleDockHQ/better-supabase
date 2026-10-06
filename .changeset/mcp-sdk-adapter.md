---
"better-supabase": minor
---

Add `better-supabase/mcp/sdk` for MCP servers on the official SDK (`@modelcontextprotocol/server` 2.3 or later, an optional peer). `createMcpAuth(betterSupabase, { resource })` verifies Supabase access tokens locally as an `OAuthTokenVerifier`, serves the RFC 9728 protected resource metadata, and `auth.serve(createMcpHandler(factory))` answers 401 and 403 challenges before the SDK sees the request. `withBetterSupabaseMcp(server, auth)` gives every `registerTool` callback `db`, `auth` and `bs` for the verified caller, and composes with `permdock/mcp`'s `protectServer`. `createMcp` stays for servers without the SDK.
