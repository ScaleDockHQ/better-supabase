# 0849: Pair any queue with any scheduler

- Status: accepted
- Date: 2026-11-13

## Context

One `QueueProvider` both held jobs and decided when schedules fired. Vercel
Queues could not schedule (`schedule` refused), and Vercel Schedules, which
replaces Vercel Cron Jobs with time zones, namespaces and queue targets, had
nowhere to plug in. An app on Vercel wants Supabase Queues or Vercel Queues
with Supabase Cron or Vercel Schedules, and the docs still told it to write a
`crons` entry for the drain.

## Decision

`createQueue` takes a `scheduler`, a `ScheduleProvider` (`apiVersion: 1`) in
`src/blocks/queue/backends.ts`: `schedule` (with tenant and probe),
`unschedule(name, tenant?)`, and the optional `listSchedules`,
`unscheduleTenant`, `dueSchedules` and `advanceSchedule`. Every
`QueueProvider` extends it, so without the option the queue's own methods run
as before, and `unschedule`'s tenant is additive. `sqlScheduler(sql, { mode })`
and `transportScheduler` are the schedule half of the SQL providers (pg_cron or
the drain), and `vercelScheduler(Schedules, { bridge })` in
`vercel-scheduler.ts` writes dynamic Vercel schedules whose payload is the job
body. `ScheduleProvider.delivers` names the queues a scheduler can reach, and
`createQueue` throws a `TypeError` for pg_cron with a queue outside the
database and for `vercelScheduler` without a bridge on a Supabase queue.

The four pairs:

- Supabase Queues with Supabase Cron is the default.
- Supabase Queues with Vercel Schedules publishes each run to a bridge topic.
  `vercelScheduleBridgeRoute` checks the probe with `schedule_has_work` and
  calls `jobs.enqueueScheduledRun`, which enqueues once per `executionId`. A
  false probe skips that run only.
- Vercel Queues with Supabase Cron uses the drain scheduler. The queue SQL
  module (version 14) adds `http_tick()`, which posts to the URL and token in
  the Vault secrets `jobs_tick_url` and `jobs_tick_token` through pg_net, and
  `blocks.queue.options.httpTick` registers it with pg_cron as
  `bsb_jobs_tick`. `jobs.schedulesRoute` runs `runSchedules`, which sends due
  runs with `sendBatch` when the client has it.
- Vercel Queues with Vercel Schedules publishes to the job's topic, and
  `vercelQueueRoute` unwraps the `ScheduleQueueMessage` and puts the run on
  `job.schedule`. A probe is refused with `invalid_request`.

Static schedules come from `vercelScheduleConfig`, which writes the `schedules`
fragment of `vercel.json`: workers as path targets (or private functions with
`schedule/v1beta`) and block timers as topic targets named
`block:<block>.<timer>` in the encoding of `vercelScheduleNameOf`, which the
routes map back to the timer. `cronRoute` takes `caller: "vercel-schedule"`
for a private drain. Doctor's BS512 reports leftover `crons`, a path in both
keys, a function target without its trigger and `httpTick` without pg_net or
the Vault secrets. `@vercel/schedules` is typed structurally (invariant 1), and
it becomes an optional peer with its range and a type check against the real
SDK together with the other new Vercel peers.

## Alternatives considered

A second provider per pair (a `vercelQueueWithSchedulesProvider`) would have
multiplied the backends instead of composing two ports. Checking the probe in
the Vercel Queues route would have run a database query from a backend that
has none. Reading a probe back from Vercel to compare schedules is not
possible: the Schedules API returns no payloads, so `ensureSchedules` writes
every definition under `vercelScheduler`. Installing `http_tick` only with
the option would have given the module two shapes; the function is always
there, revoked from `public`, `anon` and `authenticated`, and only the pg_cron
job follows the option.

## Consequences

An app picks its queue and its scheduler separately, and a pair that can't
deliver fails at `createQueue` instead of in production. Vercel Schedules
limits apply: five numeric cron fields (`vercelCronOf` converts macros and
names), a 16 KB payload, namespaces per tenant, and on Hobby one run every 15
minutes (`vercelScheduleConfig({ hobby: true })` checks it). A queue schedule
name longer than its encoding allows is hashed, and `listSchedules` can't
read it back. eve's dynamic schedules can build on `ScheduleProvider` once eve
1.0 is stable.

The schedulers cost bytes. `better-supabase/blocks/queue` grows from 72,650 to
83,244 bytes gzip (the Vercel Schedules helpers, scheduler and config builder
live in the same entry). In the Next.js example, whose server wiring loads
`createQueue` on every route, most server routes grow by about 3 KB raw (the
pair check, `enqueueScheduledRun`, `schedulesRoute`, batch sends and the SQL
schedulers), and each `vercelQueueRoute` route by about 6.4 KB raw (schedule
runs unwrapped). Both baselines are raised by that amount.
