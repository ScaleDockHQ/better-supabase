---
"better-supabase": minor
---

New block client helpers for people and scheduling: `leave.approve`, `reject` and `pending`, `shifts.rollout`, `fill` and `approveSwap`, `qualifications.check`, `consents.require`, `courses.createFromOutline` and `publish`, `medications.prescribeAndPlan`, `funding.awardsWithUsage`, `carePlans.createTree`, `bookings.book` and `bookings.public.book`. Each one calls the hooked client, so `hooks` see every step.
