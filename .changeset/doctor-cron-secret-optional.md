---
"better-supabase": patch
---

Doctor BS504 no longer asks for `CRON_SECRET` when no app source names it. The billing, outbox and
queue routes take the secret from the app, so an app that authenticates its cron routes another way,
such as `caller: "vercel-schedule"`, doesn't need the key.
