---
"better-supabase": minor
---

AI SDK surfaces for media, MCP, harness agents and tools. There are no breaking changes.

## Features

- `createMediaRoute` and `createVideoRoutes` (`better-supabase/ai-sdk/chat`) serve image, speech and video generation with an access check, the quota, metering and Storage output. The video webhook only wakes a status check.
- `mcpResourceTools`, `mcpPrompts`, `mcpPromptMessages` and `mcpEventRoute` (`better-supabase/ai-sdk/mcp`) cover MCP resources, prompts and the event webhook.
- `harnessRoute`, `steerRoute` and `harnessStateCipher` (`better-supabase/ai-sdk/agents`) run a `HarnessAgent` turn and store its resume state encrypted. `@ai-sdk/harness` is a new optional peer.
- `tenantToolsContext` and `guardTools` (`better-supabase/ai-sdk`) pass the tenant to tools and apply guardrails to tool inputs and outputs.
