---
"better-supabase": minor
---

Agent actors match support sessions. An agent `act` level reads `read_only` (`readOnly` on the actor; a non-boolean value makes the chain invalid), and `agentClaims(claims, { agent, tools, readOnly })` writes it. `tools` is now optional: a level without it delegates every tool and `tools: []` none. `createAgentRuntime({ actor })` drops the tools a delegating agent didn't list and denies a call to them with `AGENT_TOOL_NOT_DELEGATED`, which `assertToolDelegated` throws too, and a read-only agent makes the run read-only.

`actor_may_write()` decides by `kind` first: support writes only with `read_only: false`, an agent unless `read_only` is `true`, and impersonation or an unknown `kind` never. An impersonation token with `read_only: false` could write before; allow it through the provider's `authorization.functions.actorMayWrite` template instead. `read_only` is compared as a JSON boolean.

`better-supabase/testing/act-cases.json` (and `actCases` from `better-supabase/testing`) lists `act` chains with the expected verdict, so other parsers can run the same cases.
