---
"better-supabase": minor
---

Durable execution parity with Vercel Workflow, Queues and Schedules.

- `startFor` takes `retention`, `deploymentId` and `hook`. A start with a `hook` token is
  idempotent on that token and resolves to the owning run on a conflict.
- `cancelTenantRuns(tenant)` in `better-supabase/workflow-sdk` cancels a tenant's open runs, with
  `runs.cancelMany` where the World has it.
- `ScheduleProvider` gains optional `scheduleOnce`, `enableSchedule`, `disableSchedule`,
  `runScheduleNow` and `getSchedule`, and `createQueue` gains `scheduleOnce`, `enableSchedule`,
  `disableSchedule`, `runSchedule` and `getSchedule`. `vercelScheduler` implements them and
  `testScheduleProvider` checks them. A listed schedule now reports `once` and `enabled`, and a
  one-time schedule has a `nextRun`. The SQL scheduler does not implement them and answers
  `invalid_request`.
- `maintenanceRoute` and `leaseOverlap` in `better-supabase/blocks/queue`. `cronRoute` takes
  `maxLateSeconds` and `overlap`.

Upgrade: nothing breaks. A custom `ScheduleProvider` keeps working because every new member is
optional, so `apiVersion` stays 1. A `VercelSchedulesClient` fake needs `get`, `enable`, `disable`
and `invoke` only to use the new schedule methods.
