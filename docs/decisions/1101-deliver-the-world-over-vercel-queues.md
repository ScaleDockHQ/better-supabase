# 1101: Deliver the World over Vercel Queues

- Status: accepted
- Date: 2026-11-20

## Context

`pg_net` posts a delivery from the database to the flow route. eve's flow
route on Vercel has a Vercel Queues trigger and sits behind deployment
protection, and the database cannot reach a deployment URL that is not stable.
Poll delivery stops when a serverless function returns. So on Vercel none of
the first two modes delivers reliably, and the Workflow SDK's own Vercel World
is the only other route (it keeps runs in Vercel's storage, not Postgres).

## Decision

`delivery: "vercel-queue"` (or `WORKFLOW_DELIVERY=vercel-queue`) sends each
message with `@vercel/queue` to the topic that matches its queue name
(`__wkf_workflow_*`, `__wkf_step_*`, characters outside `A-Za-z0-9_-` become
`-`). The World claims no jobs, starts no poller and does not schedule the
cron job in this mode.

- The message id is the idempotency key. A delay over 23 hours becomes hops
  that send the message on without running the flow.
- A non-2xx answer retries with the World's backoff, clamped to 5 to 900
  seconds. After 73 deliveries (`MAX_DELIVERIES`) the message is acknowledged and dead-lettered through `onDeadLetter`, as in the other modes.
- Vercel authenticates the callback, so there is no `x-bsb-signature` check.
- `@vercel/queue` is an optional peer, loaded on first use (ADR 0036). The
  catalog pins 0.11.0, its newest release.
- `deliveryHeaders` (`WORKFLOW_DELIVERY_HEADERS`, or the Vault secret
  `workflow_delivery_headers` for the database dispatcher, module version 8,
  ADR 1100) adds headers such as `x-vercel-protection-bypass` to poll and
  `pg_net` deliveries, and `recoverAfter` bounds how long a run's owed wake-up
  (`wake_pending`) waits before startup recovery queues it again.

## Alternatives considered

- Poll from the eve process on Vercel. A function that returned stops
  polling, so runs wait for the next request.
- Use the Workflow SDK's Vercel World. It gives up Postgres as the store of
  runs, which the projection and the blocks rely on.
- Lower-level cron and `pg_net` with a protection bypass only. It works when a
  stable URL exists, and `deliveryHeaders` keeps that path open.

## Consequences

- The Vercel side (`handleCallback` authentication, the wildcard topic
  trigger, deployment pinning and the function timeout) is covered by unit
  tests with a fake client and is unproven on Vercel until a maintainer runs
  `scripts/eve-vercel-check.ts` on a project with Vercel Queues enabled.
- `delivery: "poll"` on Vercel logs a warning.
