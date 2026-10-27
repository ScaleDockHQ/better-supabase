---
"better-supabase": minor
---

`better-supabase/eve` runs eve tools as the session's user. `supabaseTool` wraps a tool for eve's `defineTool` and gives its `execute` the repositories from `server.forContext()`, with the agent's `act` claim and the permission keys named in `scopes`. `eveContext` builds that context, and `tenantToolApproval` applies the tenants' `auto`, `ask` and `deny` tool policies.

`approvalPolicy` is a tool `approval` backed by the approvals block: each call files one request under `eve_tool_call`, with the steps from `blocks.approvals.options.policies.eve_tool_call.<tool>`, and an answer in eve approves or rejects as the person who gave it.

`queueSchedules` runs the queue block's schedules from one every-minute eve schedule and starts a session for each `eve` job as its user. `scheduleAgent`, `agentJobHandler`, `jobAuth` and the `eveAgentJob` schema go with it. `openApiAuth` gives `defineOpenAPIConnection` its token from a credential provider, and `tenantArgument` fills an argument with the session's organization.
