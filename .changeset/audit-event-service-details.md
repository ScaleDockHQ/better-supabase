---
"better-supabase": patch
---

`audit_event` no longer stores the server's own IP address, user agent and session for a service-role call over the Data API: for the service role and direct admin connections it takes `ip`, `user_agent` and `session_id` only from its arguments, and every other caller still gets the request's own values. It also writes no restricted row when `restricted`, `ip`, `user_agent` and `session_id` are all empty.
