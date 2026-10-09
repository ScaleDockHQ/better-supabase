---
"better-supabase": patch
---

The jobs module's pg_cron functions (`schedule_job`, `unschedule_job`, `list_schedules`) and the Workflow SDK World's `dispatch_workflow_deliveries` pass `supabase db lint` on a database without pg_cron or pg_net. They look up `cron.schedule`, `cron.unschedule`, `cron.job` and `net.http_post` with `to_regprocedure` and `to_regclass` and call them through dynamic SQL, instead of naming them, so plpgsql_check no longer reports `schema "cron" does not exist` or `schema "net" does not exist`. Their behavior with the extensions installed is unchanged. Run `better-supabase sql sync` and create a migration to pick up the new function bodies.
