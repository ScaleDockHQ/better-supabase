---
"better-supabase": minor
---

Connect agents to Supabase's MCP server and serve it from your app. `supabaseMcp()` in
`better-supabase/ai-sdk/mcp` returns the server URL for a project and the tool schemas from
`@supabase/mcp-server-supabase`, and `connectTools` takes them as `schemas` to type each tool's
input and output. `supabaseMcpHandler()` in `better-supabase/mcp/sdk` serves Supabase's MCP server
behind `createMcpAuth`: it checks the caller with `authorize`, reads the Management API token
through a `CredentialProvider` and stays read-only unless you pass `readOnly: false`.
`@supabase/mcp-server-supabase` is an optional peer (`>=0.13.0 <0.14`) loaded on first use.
