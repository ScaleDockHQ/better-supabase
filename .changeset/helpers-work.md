---
"better-supabase": minor
---

New block client helpers for work and support: `tasks.complete`, `cancel` and `reopen`, `approvals.decideForSubject` and `guarded`, `cases.tryClose`, `incidents.resolve`, `meetings.conclude`, `enrollments.restart` and `advance`, `inbox.conversations.reply` and `takeOver`, `rank.between` and `automations.installDefaults`. Each one calls the hooked client, so `hooks` see every step.
