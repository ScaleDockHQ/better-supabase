---
"better-supabase": minor
---

The organizations module's memberships guard (`assignmentGuard: "module"`) now checks only client writes, made as `anon` or `authenticated`. An app's own `security definer` functions that write memberships, such as an invitation accept that seats the invitee or a one-statement ownership transfer, no longer fail with `ORGANIZATION_SELF_ROLE` or `ORGANIZATION_ROLE_CEILING`. The module's functions check their own ceilings, so the `better_supabase.trusted` setting they used to pass the guard is gone; the checks run in a new `guard_membership_role` function as the module's owner, and the trigger function runs as the writer.
