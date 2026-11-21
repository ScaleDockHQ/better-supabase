# 1130: Record the Vercel audit and what it builds

- Status: accepted
- Date: 2026-11-21

## Context

ADR 0850 chose structural adapters for Vercel's SDKs. Since then the SDKs moved on and the
repository added the Marketplace environment, Workflow, Queues and Connect integrations. An audit
of every Vercel SDK and product against the installed packages ranked the gaps for an app on
Supabase and Vercel. This ADR amends 0850 with the result. It changes none of its rules: each SDK
stays a structurally typed optional peer that the app passes in, with a tested range in
`tests/optional-peers.test.ts`.

## Decision

The audit gave six work packages, each with its own ADR where it made a decision.

| Package                                                                                    | State here                                         | Verdict                    |
| ------------------------------------------------------------------------------------------ | -------------------------------------------------- | -------------------------- |
| Project on Vercel: Marketplace env names, deployment URL, `doctor --vercel`, bypass header | Built                                              | ADR 1135                   |
| Cache invalidation outside the process, Runtime Cache and CDN adapters, `bsb.public()`     | Built                                              | ADR 1131                   |
| Observability: `vercelMetrics`, `onRequestError` bridge, workflow lifecycle events         | Built                                              | No ADR, entries documented |
| AI Gateway per organization: typed options, policy, budget, cost rows, virtual models      | Built on `settings` and `usage`, no new SQL module | ADR 1132                   |
| Durable execution: start options, tenant cancel, schedule controls, `maintenanceRoute`     | Built, additive only                               | ADR 1133                   |
| Agents on Supabase: sandbox network policy, Connect events, `connectAuth`, Chat history    | Built in part                                      | ADR 1134                   |

Skipped, with the reason:

- The Supabase World does not implement `runs.cancelMany` or `events.createBatch`: the SDK falls
  back to single calls and another pull request owns the World's delivery contract.
- The SQL scheduler has no one-time or enable and disable support yet: it needs a migration.
- An eve sandbox provider and per-tenant snapshot ids: eve's Vercel sandbox covers them.
- Packages 7 to 11 of the plan (workload identity, AI SDK surfaces, platform SDKs, frameworks,
  docs for agents) belong to a later change and ADRs from 1150.

Not building, as decided before: a Board bridge (`@vercel/board` is experimental), Global Config,
Bot Management rulesets, Vercel Agent, Drop and the Vercel Plugin (ADR 0850), Vercel CI and
Daemons (beta), a Drains receiver (Trace Drains already carry our spans), and Sign in with Vercel,
Services, Microfrontends, Flags Project Connections, WebSockets and stdio MCP (no data library
surface).

## Alternatives considered

- One ADR per SDK: it would repeat the same rule six times.
- Build every audit finding at once: the identity and framework work needs a spike first.

## Consequences

The audit has one place to read, and each skipped item names the change that would revisit it.
