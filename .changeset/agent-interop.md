---
"better-supabase": minor
---

Agents can check out, be discovered and be called by other agents.

- New `agent-checkout` block (`better-supabase/blocks/agent-checkout`): ACP and UCP checkout sessions over an orders cart with idempotency keys, AP2 mandates signed and verified with `signing-keys`, and an x402 `paymentRequired` and `withPayment` helper. The permission keys are `agent-checkout.read`, `agent-checkout.write` and `agent-checkout.manage`.
- `better-supabase/blocks/agents` serves an A2A 1.0 Agent Card (`agentCard`, `agentCardResponse`) and a JSON-RPC task endpoint (`createA2AHandler`) that maps A2A tasks to ai-chat runs.
- New `better-supabase/webmcp` subpath: `registerWebMcpTools` registers the block actions a user may run as WebMCP tools, and `mcpToolsOf` offers the same actions to `createMcp`.
- `SPEC_PINS` gains `acp`, `ucp`, `ap2`, `x402`, `a2a` and `webmcp`.

Run `better-supabase add agent-checkout` and generate a migration.
