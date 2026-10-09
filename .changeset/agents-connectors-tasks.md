---
"better-supabase": minor
---

The `agents`, `connectors` and `ai-tasks` SQL modules store assistants, their MCP servers and scheduled prompts, and `better-supabase/eve` runs eve agents on Supabase.

- `createAgents` in `better-supabase/blocks/agents` stores agents with instructions, model, tools, connectors and knowledge scopes, private until published.
- `createConnectors` in `/blocks/connectors` stores an organization's MCP servers, a grant per user behind a `credential_ref`, and tool lists an admin approves. `createAiTasks` in `/blocks/ai-tasks` runs prompts on a cron.
- `better-supabase/ai-sdk/agents` adds `createAgentRuntime` and `moderationMiddleware`, and `/ai-sdk/mcp` adds `authorizeConnector`, `connectTools` and `connectAll` (`@ai-sdk/mcp` is an optional peer).
- `better-supabase/eve` (Node only, `eve` is an optional peer) adds `supabaseAuth`, `credentialAuth`, `supabaseMemory`, `persistSessions` and `routeInbox`.
- Only the service role sets a task's `next_run_at`, a task's chat must be its user's and its agent the user's own or published, and `drain()` runs every claimed task before it reports the first error.
