---
"better-supabase": patch
---

`bs.middleware()` from `better-supabase/orpc` now type-checks in `.use()` on a single contract procedure with a typed output, so a contract-first router can guard one procedure with `permission`, `roles` or `requireTenant`. The oRPC docs show the pattern and explain that the `authorizer` passed to `createOrpc` decides every permission.
