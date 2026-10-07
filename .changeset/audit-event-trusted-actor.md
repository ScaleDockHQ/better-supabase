---
"better-supabase": minor
---

`better_supabase.audit_event` takes `actor_kind`, `actor_label`, `ip`, `user_agent` and `session_id`. Like `actor_id`, they are honoured only for the service role and direct admin connections, so a job, webhook handler or admin tool can record who acted and from where; every other caller gets the values from its JWT and request headers. `ip`, `user_agent` and `session_id` go to the restricted table.
