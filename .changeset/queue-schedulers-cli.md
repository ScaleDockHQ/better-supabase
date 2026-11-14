---
"better-supabase": minor
---

`better-supabase add` and `init` print the wiring of each queue and scheduler pair when the queue block is installed, and the `schedules` fragment of `vercel.json` for the workers that run on a cron. Doctor BS512 (warning) reports queue schedule wiring that misses or doubles runs: a path `vercel.json` still calls from `crons`, a path in both `crons` and `schedules`, a schedule on a private function without a `schedule/v1beta` trigger, and `blocks.queue.options.httpTick` without `pg_net` or the `jobs_tick_url` and `jobs_tick_token` Vault secrets.
