# 1022: Move eve to its first 1.0 release candidate and store its dynamic schedules in the queue block

- Status: accepted
- Date: 2026-11-14
- Amends: 0848, 0850

## Context

ADR 0848 held eve at 0.83.3 and Workflow at 5.4.0: the eve 1.0 release
candidates and Workflow 5.5 need Vercel packages that dropped the provenance
their earlier releases had, so `trustPolicy: no-downgrade` rejects them until
`trustPolicyIgnoreAfter` (30 days) trusts them. ADR 0850 deferred a
queue-backed provider for eve's `defineDynamicSchedules` until eve 1.0.

The maintainer approved two `trustPolicyExclude` entries to unblock both
upgrades, `@vercel/connect@2.7.0` (eve 1.0 peers on `^2.7.0`) and
`@vercel/functions@3.11.1` (`@workflow/core` 5.5.0 depends on `^3.11.1`), on
the condition that no other package needs one. An install with those two
entries fails on a third package: `@vercel/connect` 2.7.0 pins
`@vercel/oidc` 4.0.5 and `@vercel/functions` 3.11.1 pins `@vercel/oidc` 4.0.8,
and pnpm rejects both as a trust downgrade. Every `@vercel/functions` release
from 3.11.1 on pins an `@vercel/oidc` newer than 4.0.1, and Workflow 5.5 has a
single release, so no older patch avoids it. Among the eve 1.0 release
candidates, rc.1 and later peer on `@vercel/connect ^2.7.0`; rc.0 peers on
`^2.5.2`, and `@vercel/connect` 2.5.2 pins the trusted `@vercel/oidc` 4.0.1.
2.5.2 was published on 2026-10-15, so it passes `trustPolicyIgnoreAfter` from
2026-11-14 without an exclusion.

eve 1.0 changes contracts the adapter follows: the session stream moves to
version 27, connection auth declares `principalType` instead of
`credentialOwner`, an approval answer is `approve` or `deny` and names an
`interactionId`, `ApprovalStatus` gains object forms, memory tools are a
`MemoryToolSet`, and `eve build` rejects a tool input schema it can't turn
into JSON Schema.

For dynamic schedules, eve 1.0's `ScheduleProvider` contract is unchanged
from 0.83 in the part that matters: eve passes a delivery `target` only with a
management call (`create`, `list`, `invoke` and the rest), and its `deliver`
reads eve's agent bundle from the active context, which only a session turn
has. A static schedule's `run` and a route handler have no bundle. eve's own
provider fires timed runs through an internal Vercel Queues consumer route. For
self-hosted production, eve's docs point to an application-managed pattern: a
minute `defineSchedule` that claims due rows and starts sessions with
`to(...).send(...)` as the creator.

## Decision

The default catalog pins `eve` 1.0.0-rc.0 and `@vercel/connect` 2.5.2, and the
peers become `eve >=1.0.0-rc.0 <2` and `@vercel/connect >=2.5.2 <3`.
`pnpm-workspace.yaml` gets no `trustPolicyExclude` entry, and
`minimumReleaseAge` is untouched. `workflow` stays on 5.4.0, `@workflow/world`
on 5.1.0, `@workflow/world-postgres` on 5.1.1 and `@vercel/functions` on
3.10.1. eve 1.0.0-rc.0 bundles `@workflow/core` 5.2.3, the same as 0.83.3, so
the Supabase World on the 5.1 protocol keeps working with it; rc.13 bundles
5.5.0, which is one more reason the later release candidates move with
Workflow 5.5. AGENTS.md lists eve under "Pre-release pins".

`better-supabase/eve` follows the 1.0 contracts: `persistSessions` handles
`session.started`, `turn.started`, `delivery.consumed`, `content.completed`
(text parts; a part outside the `reply` phase is stored as interim) and
`turn.settled`; `credentialAuth` returns `principalType`;
`EveApprovalResponseContext` names `interactionId` and the `deny` decision;
`EveApprovalStatus` takes the object forms; `EveMemoryTool.inputSchema` is a
JSON Schema object. `optional-peers.test-d.ts` checks each shape, the hook map
included, against eve's types. No better-supabase extension interface changes,
so no `apiVersion` moves.

`queueScheduleProvider({ scheduler })` is an eve `ScheduleProvider` over a
queue block `ScheduleProvider` (ADR 0849). Each eve schedule is one queue
block schedule named `eve:<collection>:<namespace>:<name>` on the
`eve_schedules` queue, whose payload is an `EveScheduleRun`: eve's stored
payload with the timing, state, timestamps and an optional tenant from
`tenantOf(scope)`. A `single` time becomes the cron of its local minute and
completes after its run. Reads list the schedules by prefix, so the provider
needs a scheduler that returns payloads, which today is the drain scheduler:
eve's `update` keeps the stored payload and `invoke` delivers it. It throws a
`TypeError` for a scheduler without `listSchedules` and an `unsupported`
`DbException` for one that lists without payloads (pg_cron, Vercel Schedules).
eve rejects a provider object with keys beyond its contract, so the run store
`queueDynamicSchedules` needs sits in a module `WeakMap` keyed by the
provider. `invoke` delivers through the target eve passes.

`queueDynamicSchedules({ queue, provider, collections })` is the `run` of a
minute schedule and implements eve's application-managed pattern with the
definition's own callbacks: it calls `runSchedules`, drains `eve_schedules`,
reads each schedule again (a paused or deleted one is skipped), validates the
payload with `inputSchema` unless `preparePayload` shaped it, calls `auth`
with the creator and then `run`, whose `to()` sends through the minute
schedule's `to()` as the creator, with an idempotency key from the occurrence
and the message. It mirrors eve's dispatch rules: `null` from `auth`, a
different creator, an invalid payload or an unknown collection fail the
occurrence for good with `occurrence.failed`; a thrown error retries the job,
and its last attempt reports `occurrence.failed`; success reports
`occurrence.dispatched` with the session ids.

## Alternatives considered

- Add `trustPolicyExclude` entries for `@vercel/oidc` 4.0.5 and 4.0.8 next to
  the two approved ones. The approval covered two packages and asked to stop
  before a third; the maintainer can approve them, and then eve's newest
  release candidate and Workflow 5.5 land as a catalog bump.
- Override `@vercel/oidc` to 4.0.1 under `@vercel/functions` and
  `@vercel/connect`. It keeps the trust policy but runs both packages on an
  `@vercel/oidc` older than the exact version they pin, which no test covers.
- Call eve's internal `dispatchScheduledOccurrence` or keep the `deliver`
  closure from an earlier management call. Neither is public, and the closure
  fails outside a session turn.
- A record table for the dynamic schedules, so pg_cron and Vercel Schedules
  could fire them. pg_cron reads every schedule in UTC and keeps no tenant, so
  it can't run most eve schedules even with a table, and the drain scheduler
  pairs with both Supabase Queues and Vercel Queues already.
- Wait for 1.0 or until 2026-12-09 to do everything at once. The adapter would
  stay on 0.83 for a month although rc.0 installs today.

## Consequences

Apps move to eve 1.0 with 0.67 (`migration/0.66-to-0.67.mdx`). eve's dynamic
schedules run on the queue block with the drain scheduler, on Supabase or
Vercel Queues, at minute resolution. A session `queueDynamicSchedules` starts
is a session of the minute schedule: `ctx.session.schedule` names that
schedule, and eve still lets the session ask for input that nobody will
answer, so scheduled work needs tools that don't wait for a person.

Two upgrades wait on the trust policy. eve's later release candidates need
`@vercel/connect` 2.7.0 (trusted after 2026-11-30 00:48 UTC) and its
`@vercel/oidc` 4.0.5 (after 2026-11-28 19:38 UTC); Workflow 5.5 needs
`@vercel/functions` 3.11.1 (after 2026-12-09 17:48 UTC) and its
`@vercel/oidc` 4.0.8 (after 2026-12-09 17:48 UTC). After 2026-12-09 both are
a catalog bump without exclusions: Workflow 5.5.0 with `@workflow/world` and
`@workflow/world-postgres` 5.2.0, `@workflow/world-testing` 5.1.0 and
`@workflow/vitest` 5.0.9, the Supabase World on the 5.2 protocol, and eve's
newest release candidate, whose `ScheduleProvider` also takes an optional
`validateExpression` that `queueScheduleProvider` can add then. Revisit the
firing path if eve publishes a delivery entry point for custom providers.
