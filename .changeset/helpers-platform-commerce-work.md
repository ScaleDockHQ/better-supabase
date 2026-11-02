---
"better-supabase": minor
---

New block client helpers: `entitlements.require` and `entitlements.all`, `usage.canConsume`, `deals.moveStage` and `tasks.move`. Each one calls the hooked client, so `hooks` see every step.
