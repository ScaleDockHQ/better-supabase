---
"better-supabase": minor
---

`devDrain({ url, secret, every })` from `better-supabase/blocks/jobs` calls a `drainRoute` on an interval (every minute by default) in local development, where no cron caller runs, so outbox relays and queued jobs run under `next dev`. It skips a call while the last one runs, reports failures to `onError` and stops with `stop()` or an aborted `signal`. `devDrainSecret(env, name)` returns the route's secret (`CRON_SECRET` by default) or generates one and writes it to `env`.
