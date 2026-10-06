---
"better-supabase": minor
---

Expired data exports can be purged: `createOrganizationPurger(...).purgeExports({ limit })` removes the files of exports past `expires_at` from Storage, then their rows. The `data-lifecycle` module adds `expired_data_exports` and `forget_data_exports` for the service role.
