---
"better-supabase": patch
---

The `security invoker` wrappers that `sql.modules.<module>.api` writes revoke execute from `anon` (and from `authenticated` or `service_role` when the module function isn't granted to them), not only from `public`. An API schema with default privileges that grant every new function to `anon` no longer exposes member and service functions such as the webhooks-in and webhooks-out wrappers to anonymous callers.
