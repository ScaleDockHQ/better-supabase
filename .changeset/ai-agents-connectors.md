---
"better-supabase": minor
---

The `agents` SQL module and `createAgents` in `better-supabase/blocks/agents` store assistants with their own instructions, model, tools, connectors, knowledge scopes and starters. An agent is private until published to the organization or a public store, where users install and rate it.

The `connectors` SQL module and `createConnectors` in `better-supabase/blocks/connectors` store an organization's MCP servers, one grant per user behind a `credential_ref` that is revoked with the grant or server, MCP sessions per chat, and fingerprints of each tool list that an admin approves when it changes. The `ai-tasks` SQL module and `createAiTasks` in `better-supabase/blocks/ai-tasks` run prompts on a cron in the user's time zone, through the `ai_task_run` queue when `jobs` is installed or `drain` without it.

`better-supabase/ai-sdk/agents` adds `createAgentRuntime`, which builds a `ToolLoopAgent` from an agent with tool approvals and a knowledge search tool, and `moderationMiddleware`. `better-supabase/ai-sdk/mcp` adds `authorizeConnector` and `completeConnector` for OAuth with dynamic client registration in Vault, and `connectTools` and `connectAll`, which reuse the stored session and return only approved tools. `@ai-sdk/mcp` is a new optional peer.
