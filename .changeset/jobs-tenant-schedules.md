---
"better-supabase": minor
---

The jobs block works with any external scheduler under `scheduler: "drain"`. Schedules record a tenant (`tenant` or the tenant of `context`), `jobs.listSchedules({ prefix, tenant })` returns their next and last run, and `jobs.unscheduleAll({ tenant })` removes a tenant's schedules. `drainRoute` takes `monitor` hooks (`onStart`, `onFinish`) for cron check-ins, and its result reports `errors`. The `jobs` module is at version 4: `schedule_job` takes a tenant, and `list_schedules` and `unschedule_tenant` are new; run `better-supabase sql upgrade`.
