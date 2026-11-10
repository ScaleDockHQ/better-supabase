---
"better-supabase": minor
---

The authorization provider's `functions.managedUsers` template takes `{tenant}`, so a provider that keeps a manager chain per tenant can write `authz.managed_user_ids({tenant})` and a manager in one organization never reaches reports in another. `{tenant}` is optional: a template without placeholders still passes `testAuthorizationProvider`, and `apiVersion` stays 1. No module reads `managedUsers` yet, so nothing changes in the generated SQL and no migration is needed.
