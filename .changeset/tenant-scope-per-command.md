---
"better-supabase": minor
---

The restrictive tenant scope is now one policy per command (`bsb_tenant_scope_select`, `_insert`, `_update` and `_delete`), each `to public` instead of `to authenticated` (ADR 0104). A permissive policy that reaches `anon` or `public` can no longer read across organizations, and a branch one command grants no longer satisfies another. Policies that grant `anon` or `public` on a tenant table keep working because their conditions stay inside the matching scope policy. `upgrade` drops the old `for all` policy and writes the four new ones; run `supabase db schema declarative sync` for the migration. Breaking for apps that relied on an open `anon` or `public` policy on a tenant table without a condition the block knows about.
