---
"better-supabase": minor
---

Authorization providers can set `functions.roleIn` (`{role}`, `{tenant}`): whether a role belongs to a tenant, declared or a custom role the tenant owns. With `blocks.memberships.options.roles.many` under the provider model, a trigger on `membership_roles` then refuses any other role on every write, the service role's included, with SQLSTATE 23514 and `MEMBERSHIP_ROLE_SCOPE`, so a custom role of another organization can't be stored. Providers without the template keep today's behaviour.
