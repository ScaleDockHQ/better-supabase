# 0113: Run eve tools as the user, approve them in the approvals block and schedule them on the queue

- Status: accepted
- Date: 2026-10-27

## Context

`better-supabase/eve` covered the World, sign-in, MCP connections, memory,
sessions and the inbox, but an eve agent still had no way to touch the app's
data as the person it works for. A tool either used the service role, which
skips row-level security, or rebuilt the user's token by hand. eve's own
approvals (`once()`, `always()`) live in the session and have one approver,
so a tenant could not route a risky call to its owners. eve's schedules are
fixed crons in code, with no tenant, time zone or user. And eve 0.71 added
OpenAPI connections, which take the same `auth` as MCP connections and can
fill arguments the model never sees.

## Decision

`supabaseTool` wraps eve's tool definition: `execute` gets `db` from
`server.forContext(eveContext(...))`, the session's user and tenant with the
agent as the outer `act` level. Agent claims are delegated
(`permissions-delegation`), so `eveContext` takes `scopes` for the keys the
agent may use; without them the token holds none. `runAs` names the user for
a principal that isn't one. The tenants' `auto`, `ask` and `deny` policies
from the AI chat block apply through `tenantToolApproval`, inline, so the
entry still imports nothing from `ai`.

`approvalPolicy` is an eve tool `approval` over the approvals block. A call
files one request with the subject `{ type: "eve_tool_call", id: callId }`
and the tool name as the action, so `policies.eve_tool_call.<tool>` sets the
steps and a replay finds its request. The agent gets `approvals.read` and
`approvals.request` added to its scopes. An answer in eve's prompt approves
or rejects as the person who gave it, through `forContext`, and settles the
call only when the request reaches a matching final status.

`queueSchedules` is the `run` of one every-minute eve schedule: it calls the
queue block's `runSchedules()`, since `drain` doesn't enqueue due schedules,
then drains the `eve` queue (`eveAgentJob`) and sends each job's prompt to
its channel target as the job's user (`jobAuth`). `scheduleAgent` writes the
schedule with the tenant, time zone and user context.

`openApiAuth` is `credentialAuth` for `defineOpenAPIConnection`, and
`tenantArgument(name)` fills one provided argument with the session's
organization. The eve example gains a tool behind an approval, the schedule
and an OpenAPI connection, and the fixture's approvals config gets the
`eve_tool_call.add_note` policy.

The catalog pin stays at eve 0.83.2: 0.84.0 is younger than
`minimumReleaseAge`. The peers range stays `>=0.71 <1`, because every eve
API used here (`providedArguments`, `defineOpenAPIConnection`, the approval
`response` hook, the schedule `run` arguments) shipped in 0.71.

## Alternatives considered

- Run tools as the service role and filter by tenant in TypeScript. It
  skips row-level security, and every tool repeats the checks.
- Wrap `agentTools` and `agentToolApproval` from `better-supabase/ai-sdk`.
  They import `ai` at load time, which the eve entry avoids.
- Keep approvals in eve's session state. One person answers, and the
  tenant's approvers, steps and audit trail in the approvals block go unused.
- One eve schedule per tenant schedule. eve's schedules are fixed at build
  time, so a tenant could not add one.

## Consequences

Tools, approvals and schedules run under the same policies as the app's own
requests, and a tenant changes who approves a tool in config. A decision in
the approvals block's own UI doesn't settle eve's open prompt; the call
settles when someone answers in eve, or when a replay reads the final
status. A drain runs inside the schedule's task, bounded by `budgetMs`. We
revisit the approvals bridge if eve adds a way to resolve a prompt from
outside the session.
