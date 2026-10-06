---
"better-supabase": minor
---

Feature flags can be managed from an admin page over the Data API. The `flags` module adds `list_flags`, `save_flag`, `delete_flag` and `set_flag_override`, for platform staff with `flags.manage` (a new platform permission, checked when the `access` module is installed) or the service role, granted to `authenticated` so `sql.modules.flags.api` writes wrappers for them. `createFlagAdmin({ transport })` in `better-supabase/blocks/flags` calls them.
