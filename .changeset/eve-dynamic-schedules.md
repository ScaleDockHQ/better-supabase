---
"better-supabase": minor
---

`queueScheduleProvider({ scheduler })` from `better-supabase/eve` is a
provider for eve's `defineDynamicSchedules` that stores each schedule as a
queue block schedule on the `eve_schedules` queue, so members and the model
manage them with eve's tools while the drain scheduler keeps their time zone,
tenant and payload. `queueDynamicSchedules({ queue, provider, collections })`
is the `run` of a minute `defineSchedule`: it enqueues the due runs, then
calls each definition's `auth` and `run` as the schedule's creator, with
eve's retry and `occurrence.dispatched` and `occurrence.failed` rules.
`eveScheduleRun` is the queue's schema. The provider needs a scheduler that
lists schedules with their payloads, such as
`sqlScheduler(sql, { mode: "drain" })`.
