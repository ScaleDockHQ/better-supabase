---
"better-supabase": patch
---

With an authorization provider that sets `authorization.functions.actorMayWrite`, the blocks replace calls to `better_supabase.actor_may_write()` with the provider's check but keep the function's own `create function`, `grant` and `revoke` statements. The created-by block file no longer renders `create or replace function (provider_check())`, which failed with a syntax error.
