---
"better-supabase": minor
---

`createAgentRuntime` from `better-supabase/ai-sdk/agents` takes `caller` (the invoking user, always the principal; the agent is only the actor), `authorizeModel` (checked before every model call, refusing with `forbidden` before tokens are spent), `results` (filters knowledge hits before the model sees them), `operations`, `permissions` and `authorizeTool` (each tool is the operation `ai.tool.<name>`, the provider's entry wins, and `high` risk waits for approval), and `gateway` (AI Gateway `user` and tags from the caller). `searchTool` and `recallTool` take `results` too. Breaking: `gatewayOptions` drops a `user` passed in its second argument, so `user` only ever comes from `context.userId`; pass the caller's id there. `GatewayContext` takes `tags`.
